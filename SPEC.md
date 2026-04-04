# Pheme — Product & Technical Specification

> Vietnamese-optimized AI meeting notes for macOS.
> Record meetings, get real-time transcripts, auto-generated summaries.
> Named after Pheme (Φήμη) — Greek goddess of voice and speech.

**Repo:** `sonpiaz/pheme`
**Domain:** `pheme.so` (or `pheme.ai`)
**Bundle ID:** `com.sonpiaz.pheme`
**Platform:** macOS 14.2+ (Sonoma)
**Language:** Swift 5.9
**Dependencies:** None (all native Apple frameworks)

---

## 1. Product Vision

### What is Pheme?
A native macOS app that captures meeting audio (mic + system audio), shows real-time transcript, and auto-generates structured summaries — optimized for Vietnamese (80%) + English (20%) mixed language.

### Why Pheme?
- **Granola** ($14/mo, $1.5B valuation) proves the market — but Vietnamese support is poor (uses Deepgram/AssemblyAI which are weak for Vietnamese)
- **Yap** (our push-to-talk app) proves `gpt-4o-transcribe` works excellently for Vietnamese
- No competitor focuses on Vietnamese meeting notes
- Privacy-first: no bot joins calls, audio discarded after transcription

### Target Users
- Vietnamese startup teams (product, marketing, engineering)
- Mixed Vietnamese/English meetings
- Solo professionals who attend online meetings
- Students attending lectures/classes

### Competitive Advantage
| vs Granola | vs Otter.ai | vs Fireflies |
|-----------|-------------|-------------|
| Vietnamese-optimized STT | No bot joins meeting | No bot joins meeting |
| `gpt-4o-transcribe` > Deepgram for Vietnamese | Privacy-first | Privacy-first |
| Open source | Native macOS (not Electron) | Native macOS |

---

## 2. Core Features (MVP)

### 2.1 One-Click Recording
- Start/stop recording from main window or menu bar
- Captures both microphone (user's voice) and system audio (other participants)
- Visual recording indicator (red dot, timer, audio levels)
- Sound feedback on start/stop (reuse Yap's harmonic chords)

### 2.2 Real-Time Transcript
- Live scrolling transcript as people speak
- Speaker labels: "Me" (mic) vs "Them" (system audio)
- Color-coded: blue tint for "Me", neutral for "Them"
- Timestamps on each segment
- Auto-scroll with scroll-lock when user scrolls up
- Supports Vietnamese + English mixed language

### 2.3 Auto Summary
- Generated automatically when recording ends
- Structured sections:
  - **Key Points** — main discussion topics
  - **Decisions** — what was decided
  - **Action Items** — who does what, deadlines if mentioned
- Auto-generated meeting title
- Bilingual-aware: summary matches transcript language
- "Regenerate" button to re-run with different prompt

### 2.4 Meeting History
- All meetings persisted locally (SwiftData/SQLite)
- Grouped by date: Today, Yesterday, This Week, Earlier
- Search across titles and transcript content
- Each meeting shows: title, date, duration, summary preview

### 2.5 Raw Transcript View
- Full word-for-word transcript with speaker labels
- Copy full transcript button
- Searchable within a meeting

### 2.6 Menu Bar Presence
- Menu bar icon shows recording state (waveform idle, red dot recording)
- Quick actions: Start/Stop Recording, Open Pheme
- Last 3 meetings for quick access

---

## 3. Architecture

### 3.1 Decision: New Standalone App
Not an extension of Yap because:
- Fundamentally different interaction model (long-running recording vs hold-to-talk)
- Yap stores all audio in RAM (incompatible with 60+ min recordings)
- Yap's pipeline is tightly coupled to hotkey-hold-release cycle
- However, many Yap components are directly reusable

### 3.2 App Type: Hybrid
- **Menu bar**: always visible, shows recording state, quick controls
- **Main window**: full 3-column UI (meeting list + transcript + summary)
- Same pattern as Yap's `MenuBarExtra` + `NSWindow` hybrid

### 3.3 Signal Flow

```
┌─────────────────────────────────────────────────────────────┐
│                      PhemeApp                                │
│                                                              │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────────┐  │
│  │   Mic    │───▶│              │───▶│  WebSocket #1     │  │
│  │ Recorder │    │  Audio       │    │  (Me stream)      │  │
│  └──────────┘    │  Chunker    │    └─────────┬─────────┘  │
│                  │  (PCM16LE   │              │             │
│  ┌──────────┐    │   base64)   │    ┌─────────▼─────────┐  │
│  │  System  │───▶│              │───▶│  WebSocket #2     │  │
│  │  Audio   │    │              │    │  (Them stream)    │  │
│  │ Recorder │    └──────────────┘    └─────────┬─────────┘  │
│  └──────────┘                                  │             │
│                                                │             │
│                     ┌──────────────────────────▼──────┐      │
│                     │  TranscriptionSession            │      │
│                     │  - Merge segments by timestamp   │      │
│                     │  - Update SwiftData models       │      │
│                     │  - Drive LiveTranscriptView      │      │
│                     └──────────────┬──────────────────┘      │
│                                    │ (on recording end)      │
│                     ┌──────────────▼──────────────────┐      │
│                     │  SummaryGenerator                │      │
│                     │  - Send transcript to GPT-4o-mini│      │
│                     │  - Generate title + summary      │      │
│                     │  - Update Meeting model          │      │
│                     └─────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Tech Stack

### 4.1 System Audio Capture: Core Audio Taps

**API:** `CATapDescription` (macOS 14.2+)

**Why not alternatives:**
- ScreenCaptureKit: requires screen recording permission (misleading UX), wastes resources capturing video then discarding it, known crash bugs on long sessions
- Virtual audio driver: requires kernel extension or DriverKit, complex to install/maintain
- Core Audio Taps: purpose-built for audio-only capture, Apple-recommended, no screen recording prompt

**Implementation approach:**
1. Create `CATapDescription` targeting all processes (excluding Pheme itself)
2. Run two separate `AVAudioEngine` instances:
   - Engine 1: mic input (reuse Yap's AudioRecorder pattern)
   - Engine 2: Core Audio Tap device (system audio)
3. Both output 16kHz mono PCM16LE chunks via callback
4. Mic = "Me", System = "Them" (natural speaker diarization)

**Permission:** Uses `com.apple.security.device.audio-input` entitlement + runtime consent dialog. Non-sandboxed app (same as Yap: `ENABLE_HARDENED_RUNTIME: false`).

**Reference implementations:**
- Apple sample: "Capturing system audio with Core Audio taps"
- `github.com/insidegui/AudioCap`
- `github.com/makeusabrew/audiotee`

### 4.2 Real-Time STT: OpenAI Realtime API

**Endpoint:** `wss://api.openai.com/v1/realtime?intent=transcription`
**Model:** `gpt-4o-transcribe`
**Transport:** Native `URLSessionWebSocketTask` (no dependencies)

**Why OpenAI Realtime API:**
- `gpt-4o-transcribe` is proven best for Vietnamese in Yap
- True streaming via WebSocket (not polling)
- Built-in Voice Activity Detection (VAD)
- No external dependencies needed

**Protocol flow:**
```
1. Connect WebSocket
2. Send session.update:
   {
     "model": "gpt-4o-transcribe",
     "input_audio_transcription": {
       "model": "gpt-4o-transcribe",
       "language": "vi"
     },
     "turn_detection": {
       "type": "server_vad",
       "silence_duration_ms": 700,
       "threshold": 0.5
     }
   }
3. Stream audio: input_audio_buffer.append (base64 PCM16LE, 100ms chunks)
4. Receive: conversation.item.input_audio_transcription.delta → update UI
5. Receive: conversation.item.input_audio_transcription.completed → mark final
6. On stop: input_audio_buffer.commit → close connection
```

**Two-stream design:**
- WebSocket #1: mic audio → segments tagged as `.me`
- WebSocket #2: system audio → segments tagged as `.them`
- `TranscriptionSession` merges by timestamp

**Audio format:** 16kHz mono PCM16LE (same as Yap's converter output, compatible with OpenAI Realtime API)

**Resilience:**
- Ping every 30 seconds for keepalive
- Auto-reconnect on disconnect with exponential backoff (1s, 2s, 4s, max 16s)
- Buffer ~5 seconds of audio locally during reconnection
- Persist transcript segments to SwiftData incrementally (not just at end)

### 4.3 Summary Generation: OpenAI Chat Completions

**Model:** `gpt-4o-mini`
**Endpoint:** `https://api.openai.com/v1/chat/completions`

**Two calls on recording end:**

**Call 1 — Title generation:**
```
System: "Generate a concise meeting title (max 8 words) from this transcript.
         Use the same language as the transcript. Output ONLY the title."
User: [first 2000 chars of transcript]
```

**Call 2 — Summary generation:**
```
System: "You are a meeting assistant. Analyze the transcript and generate a
         structured summary. The transcript may be in Vietnamese, English, or mixed.
         Generate the summary in the same primary language.

         Format:
         ## Key Points
         - [bullet points of main discussion topics]

         ## Decisions
         - [bullet points of decisions made, if any]

         ## Action Items
         - [ ] [task] — [person responsible, if mentioned]

         ## Follow-ups
         - [items that need follow-up]

         Be concise. Skip sections if not applicable."
User: [full transcript with speaker labels]
```

**Temperature:** 0.3 (deterministic)
**Max tokens:** 2048

### 4.4 Data Storage: SwiftData

**Why SwiftData:**
- Native to macOS 14+ (our target)
- SQLite under the hood — reliable, fast
- Zero external dependencies
- `@Query` + `@Model` integrate naturally with SwiftUI
- Future CloudKit sync is trivial to add

**Storage location:** `~/Library/Application Support/Pheme/`

**Storage estimates:**
- 1-hour meeting ≈ 6,000 words ≈ 36KB text
- 1,000 meetings ≈ 36MB — trivial for SQLite
- No audio stored (privacy-first)

---

## 5. Data Model

```swift
import SwiftData

// MARK: - Meeting

@Model
final class Meeting {
    var id: UUID = UUID()
    var title: String = ""
    var summary: String?                           // markdown structured summary
    var date: Date = Date()                        // recording start time
    var duration: TimeInterval = 0                 // total seconds
    var isRecording: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.meeting)
    var segments: [TranscriptSegment] = []

    // Computed: full transcript for copy/export
    var rawTranscript: String {
        segments
            .sorted { $0.timestamp < $1.timestamp }
            .map { "[\($0.speaker.rawValue)] \($0.text)" }
            .joined(separator: "\n")
    }

    // Computed: transcript with timestamps for summary input
    var formattedTranscript: String {
        segments
            .sorted { $0.timestamp < $1.timestamp }
            .map {
                let time = formatTimestamp($0.timestamp)
                return "[\(time)] [\($0.speaker.rawValue)] \($0.text)"
            }
            .joined(separator: "\n")
    }

    private func formatTimestamp(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

// MARK: - TranscriptSegment

@Model
final class TranscriptSegment {
    var id: UUID = UUID()
    var text: String = ""
    var speaker: Speaker = .me
    var timestamp: TimeInterval = 0                // offset from meeting start (seconds)
    var isFinal: Bool = false                      // false while streaming, true when confirmed

    var meeting: Meeting?
}

// MARK: - Speaker

enum Speaker: String, Codable {
    case me = "Me"
    case them = "Them"
}
```

---

## 6. Module Structure

```
pheme/
├── README.md
├── SPEC.md                          ← this file
├── LICENSE                          (MIT)
├── Makefile                         (generate, build, run, clean)
├── project.yml                      (XcodeGen config)
├── Resources/
│   ├── Info.plist
│   ├── Pheme.entitlements
│   ├── AppIcon.svg
│   └── Assets.xcassets/
│
└── Sources/Pheme/
    │
    ├── App/
    │   ├── PhemeApp.swift            — @main, MenuBarExtra + WindowGroup
    │   └── AppDelegate.swift         — lifecycle, window management, onboarding
    │
    ├── Audio/
    │   ├── MicRecorder.swift         — AVAudioEngine mic capture, streaming output
    │   │                               (adapted from Yap: remove RAM buffer, add chunk callback)
    │   ├── SystemAudioRecorder.swift — Core Audio Tap capture for system audio
    │   │                               (CATapDescription + AVAudioEngine on tap device)
    │   ├── DualStreamMixer.swift     — manages both recorders, labels "me" vs "them"
    │   │                               (start/stop both, forward chunks to transcriber)
    │   └── AudioChunker.swift        — converts Float32 → PCM16LE → base64 chunks
    │                                   (100ms chunks = 1,600 samples at 16kHz)
    │
    ├── Transcription/
    │   ├── RealtimeTranscriber.swift — WebSocket client for OpenAI Realtime API
    │   │                               (URLSessionWebSocketTask, send audio, receive deltas)
    │   │                               (handles connect, disconnect, reconnect, keepalive)
    │   └── TranscriptionSession.swift— orchestrates dual-stream transcription
    │                                   (owns 2 RealtimeTranscriber instances)
    │                                   (merges segments by timestamp)
    │                                   (persists to SwiftData incrementally)
    │
    ├── Summary/
    │   ├── SummaryGenerator.swift    — post-recording LLM call via Chat Completions
    │   │                               (title generation + structured summary)
    │   │                               (model: gpt-4o-mini, temp: 0.3)
    │   └── SummaryPrompts.swift      — bilingual prompt templates
    │                                   (Vietnamese/English aware)
    │                                   (sections: Key Points, Decisions, Action Items, Follow-ups)
    │
    ├── Storage/
    │   ├── Meeting.swift             — @Model (see Data Model section above)
    │   └── TranscriptSegment.swift   — @Model (see Data Model section above)
    │
    ├── UI/
    │   ├── MeetingListView.swift     — left sidebar: meeting list grouped by date
    │   │                               (search bar, date grouping, duration badge)
    │   │                               (pulsing red dot on currently-recording meeting)
    │   ├── LiveTranscriptView.swift  — center: real-time scrolling transcript
    │   │                               (speaker pills, timestamps, auto-scroll)
    │   │                               (scroll-lock when user scrolls up)
    │   ├── MeetingSummaryView.swift  — right: summary + raw transcript tabs
    │   │                               (editable title, structured summary)
    │   │                               (Copy Summary / Copy Transcript / Regenerate buttons)
    │   ├── RecordingControlView.swift— bottom bar: record button, timer, audio levels
    │   │                               (dual level meters: mic + system)
    │   ├── SettingsView.swift        — settings window
    │   │                               (API key, custom dictionary, summary language)
    │   │                               (launch at login, sound feedback)
    │   │                               (adapted from Yap's SettingsView pattern)
    │   └── OnboardingView.swift      — first-launch permission wizard
    │                                   (Step 1: Microphone, Step 2: System Audio, Step 3: API Key)
    │                                   (auto-detect polling, adapted from Yap)
    │
    └── System/
        ├── SoundFeedback.swift       — COPIED from Yap (harmonic chord tones)
        ├── LaunchAtLogin.swift        — COPIED from Yap (SMAppService)
        ├── CustomDictionary.swift     — COPIED from Yap (user word list for STT prompt)
        └── PermissionManager.swift    — centralized permission checks
                                        (mic, system audio, network)
```

---

## 7. UI Specification

### 7.1 Main Window (3-column layout)

```
┌──────────────┬────────────────────────────┬──────────────────────┐
│  LEFT (200px)│  CENTER (flexible)         │  RIGHT (300px)       │
│              │                            │  (collapsible)       │
│  ┌────────┐  │                            │                      │
│  │🔴 New  │  │  [Me] 0:00:12             │  Meeting Title       │
│  │Meeting │  │  Xin chào mọi người,      │  (editable)          │
│  └────────┘  │  hôm nay mình sẽ review   │                      │
│              │  sprint...                 │  ────────────────     │
│  🔍 Search   │                            │                      │
│              │  [Them] 0:00:23            │  ## Key Points       │
│  ────────    │  OK, bắt đầu với task      │  - Sprint review     │
│  TODAY       │  authentication nhé.       │  - Auth task blocked │
│  ◉ Sprint    │                            │                      │
│    Review    │  [Me] 0:00:35              │  ## Decisions        │
│    12m       │  Task đó đang bị block     │  - Prioritize auth   │
│              │  bởi API team...           │                      │
│  YESTERDAY   │                            │  ## Action Items     │
│  ○ 1:1 with │  [Them] 0:00:48            │  - [ ] Son: follow   │
│    Tung      │  Let me check with the     │    up with API team  │
│    45m       │  API team today.           │                      │
│              │                            │  ────────────────     │
│  APR 2       │                            │  [📋 Copy Summary]   │
│  ○ Product   │  ──────────────────────    │  [📄 Copy Transcript]│
│    Planning  │                            │  [🔄 Regenerate]     │
│    32m       │  ┌────────────────────┐    │                      │
│              │  │ 🔴 0:23:45         │    │                      │
│              │  │ 🎤 ▁▃▅▇  🔊 ▁▃▅   │    │                      │
│              │  │ [⏹ Stop Recording]  │    │                      │
│              │  └────────────────────┘    │                      │
└──────────────┴────────────────────────────┴──────────────────────┘
```

### 7.2 Menu Bar

```
┌─────────────────────────────┐
│  [Pheme icon]               │  ← waveform (idle) or 🔴 (recording)
├─────────────────────────────┤
│  🔴 Recording — 0:23:45    │  ← only when recording
│  ──────────────────────     │
│  ⏹ Stop Recording          │  ← or ▶ Start Recording
│  ──────────────────────     │
│  Recent:                    │
│    Sprint Review — 12m ago  │
│    1:1 with Tung — Yesterday│
│  ──────────────────────     │
│  Open Pheme            ⌘O  │
│  Settings...           ⌘,  │
│  ──────────────────────     │
│  Quit Pheme            ⌘Q  │
└─────────────────────────────┘
```

### 7.3 Onboarding (First Launch)

```
Step 1/3: 🎤 Microphone
  "Pheme needs your mic to capture your voice in meetings."
  [Grant Access]
  → auto-detect when granted → advance

Step 2/3: 🔊 System Audio
  "Pheme needs system audio access to hear other participants."
  [Grant Access]
  → auto-detect when granted → advance

Step 3/3: 🔑 OpenAI API Key
  "Pheme uses OpenAI for transcription and summaries."
  [SecureField: sk-...]
  [Get Started]

Done: 🎉 "You're all set! Click 🔴 to start your first meeting."
```

### 7.4 Settings Window

```
┌─────────────────────────────────────┐
│  OpenAI API Key                     │
│  [sk-••••••••••••••]               │
│  Uses gpt-4o-transcribe + gpt-4o-mini │
│                                     │
│  Custom Dictionary                  │
│  [Add word...] [Add]               │
│  [Son] [Affitor] [Hidrix] [×]     │
│                                     │
│  Summary Language                   │
│  ○ Auto-detect  ○ Vietnamese  ○ English │
│                                     │
│  Transcription Mode                 │
│  ○ Realtime ($3.60/hr)             │
│  ○ Batch — 10s delay ($0.36/hr)    │
│                                     │
│  System                             │
│  [×] Launch at login               │
│  [×] Sound feedback                │
│                                     │
│  Permissions                        │
│  ✅ Microphone — Granted            │
│  ✅ System Audio — Granted          │
└─────────────────────────────────────┘
```

---

## 8. API Integration Details

### 8.1 OpenAI Realtime API (Transcription)

**Connection:**
```
URL: wss://api.openai.com/v1/realtime?intent=transcription
Headers:
  Authorization: Bearer <API_KEY>
  OpenAI-Beta: realtime=v1
```

**Session configuration (sent after connect):**
```json
{
  "type": "session.update",
  "session": {
    "input_audio_format": "pcm16",
    "input_audio_transcription": {
      "model": "gpt-4o-transcribe",
      "language": "vi",
      "prompt": "Custom vocabulary: Son, Affitor, Hidrix, Mandeck. "
    },
    "turn_detection": {
      "type": "server_vad",
      "threshold": 0.5,
      "prefix_padding_ms": 300,
      "silence_duration_ms": 700
    }
  }
}
```

**Sending audio (every 100ms):**
```json
{
  "type": "input_audio_buffer.append",
  "audio": "<base64_encoded_pcm16le_chunk>"
}
```

**Receiving transcript deltas:**
```json
{
  "type": "conversation.item.input_audio_transcription.delta",
  "delta": "Xin chào mọi"
}
```

**Receiving completed segments:**
```json
{
  "type": "conversation.item.input_audio_transcription.completed",
  "transcript": "Xin chào mọi người, hôm nay mình sẽ review sprint."
}
```

### 8.2 OpenAI Chat Completions (Summary)

**Endpoint:** `POST https://api.openai.com/v1/chat/completions`
**Model:** `gpt-4o-mini`
**See Section 4.3 for prompt templates**

---

## 9. Reuse from Yap (Detailed)

### Files to COPY as-is:
```
Yap → Pheme
Sources/Yap/Audio/SoundFeedback.swift     → Sources/Pheme/System/SoundFeedback.swift
Sources/Yap/System/LaunchAtLogin.swift     → Sources/Pheme/System/LaunchAtLogin.swift
Sources/Yap/System/CustomDictionary.swift  → Sources/Pheme/System/CustomDictionary.swift
```

### Patterns to ADAPT:

**AudioRecorder.swift → MicRecorder.swift:**
- Remove: `private var buffer: [Float] = []` (RAM accumulation)
- Remove: `func stopRecording() -> [Float]`
- Add: `var onAudioChunk: (([Float]) -> Void)?` callback
- Keep: AVAudioEngine setup, format conversion (16kHz mono Float32), tap installation, RMS level meter
- In tap callback: call `onAudioChunk?(samples)` instead of appending to buffer

**OnboardingView.swift → OnboardingView.swift:**
- Change steps: Mic → System Audio → API Key (instead of Mic → Accessibility → Input Monitoring)
- Step 3 is a SecureField for API key (not a system permission)
- Keep: polling pattern, auto-advance, progress dots, completion screen

**SettingsView.swift → SettingsView.swift:**
- Keep: Form layout, permission rows, custom dictionary (FlowLayout tag cloud)
- Remove: hotkey picker, transcription mode picker, snippets
- Add: summary language picker, transcription mode (realtime/batch), system audio permission

**project.yml → project.yml:**
- Change: bundle ID, app name, deployment target (14.2)
- Keep: XcodeGen structure, build settings, signing config

**YapApp.swift → PhemeApp.swift:**
- Change: MenuBarExtra content (recording controls vs history)
- Add: WindowGroup for main 3-column window
- Keep: AppDelegate pattern, onboarding launch logic

---

## 10. Implementation Phases

### Phase 1: Foundation (Week 1-2)
**Goal: Mic recording → real-time Vietnamese transcript on screen**

Tasks:
1. Create repo `sonpiaz/pheme`, init project structure
2. Create `project.yml` (adapted from Yap)
3. Create `Makefile` (generate, build, run, clean)
4. Create `Resources/Info.plist` + `Pheme.entitlements`
5. Implement SwiftData models: `Meeting`, `TranscriptSegment`
6. Implement `MicRecorder.swift` (streaming mode from Yap's AudioRecorder)
7. Implement `AudioChunker.swift` (Float32 → PCM16LE → base64)
8. Implement `RealtimeTranscriber.swift` (WebSocket client)
9. Implement `TranscriptionSession.swift` (single stream first)
10. Build basic UI: single window + `LiveTranscriptView` + record button
11. Wire up: record → mic → chunker → WebSocket → deltas → SwiftUI
12. Copy `SoundFeedback.swift`, `LaunchAtLogin.swift`, `CustomDictionary.swift` from Yap

**Deliverable:** App that records mic and shows live Vietnamese transcript.

### Phase 2: System Audio (Week 3)
**Goal: Capture system audio, interleaved "Me" / "Them" transcript**

Tasks:
1. Implement `SystemAudioRecorder.swift` (Core Audio Taps)
2. Implement `DualStreamMixer.swift` (manage both streams)
3. Add second `RealtimeTranscriber` instance for system audio
4. Update `TranscriptionSession` to merge dual streams by timestamp
5. Update `LiveTranscriptView` with speaker labels and colors
6. Add system audio permission to onboarding
7. Test with real Zoom/Meet/Teams calls

**Deliverable:** Interleaved "Me" / "Them" transcript from a real meeting.

### Phase 3: Summary (Week 4)
**Goal: Auto-generate title + structured summary on recording end**

Tasks:
1. Implement `SummaryGenerator.swift` (OpenAI Chat Completions)
2. Design and test bilingual prompts (`SummaryPrompts.swift`)
3. Build `MeetingSummaryView.swift` (right column)
4. Auto-title generation from transcript
5. "Regenerate" button
6. "Copy Summary" / "Copy Transcript" buttons
7. Test with Vietnamese, English, and mixed transcripts

**Deliverable:** End recording → automatic structured summary.

### Phase 4: Polish (Week 5)
**Goal: Complete app ready for daily use**

Tasks:
1. Build `MeetingListView.swift` (sidebar with date grouping, search)
2. Build menu bar extra with recording controls
3. Build `SettingsView.swift` (API key, dictionary, preferences)
4. Build `OnboardingView.swift` (adapted from Yap)
5. Add sound feedback (copy SoundFeedback from Yap)
6. Add launch at login (copy LaunchAtLogin from Yap)
7. WebSocket resilience: reconnect, keepalive, local audio buffering
8. Incremental SwiftData persistence during recording
9. App icon and branding
10. Test 30+ minute recordings for stability

**Deliverable:** Complete Pheme app for daily use.

### Phase 5: Future (Post-MVP)
- Calendar integration (EventKit) — auto-name meetings from calendar
- Batch transcription mode ($0.36/hr vs $7.20/hr)
- Local Whisper fallback for offline mode
- Meeting templates (standup, 1:1, brainstorm, etc.)
- Cloud sync via CloudKit
- Export as Markdown / PDF
- Keyboard shortcut for start/stop recording (global hotkey)
- "Ask Pheme" — chat with meeting transcript (like Granola's Ask feature)

---

## 11. Cost Analysis

### Per-Meeting Costs (Realtime Mode)

| Component | Rate | 30 min | 60 min |
|-----------|------|--------|--------|
| Realtime API — mic stream | $0.06/min | $1.80 | $3.60 |
| Realtime API — system stream | $0.06/min | $1.80 | $3.60 |
| Summary (gpt-4o-mini) | ~$0.02 | $0.02 | $0.03 |
| Title (gpt-4o-mini) | ~$0.01 | $0.01 | $0.01 |
| **Total** | | **$3.63** | **$7.24** |

### Per-Meeting Costs (Batch Mode — Future)

| Component | Rate | 30 min | 60 min |
|-----------|------|--------|--------|
| Batch API — mic stream | $0.006/min | $0.18 | $0.36 |
| Batch API — system stream | $0.006/min | $0.18 | $0.36 |
| Summary (gpt-4o-mini) | ~$0.02 | $0.02 | $0.03 |
| **Total** | | **$0.38** | **$0.75** |

### Monthly Estimates (Realtime Mode)

| Usage | Meetings/week | Avg duration | Monthly cost |
|-------|--------------|-------------|-------------|
| Light | 5 | 30 min | ~$72 |
| Medium | 10 | 45 min | ~$220 |
| Heavy | 20 | 60 min | ~$580 |

---

## 12. Entitlements & Permissions

### Entitlements (Pheme.entitlements)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

### Info.plist Keys
```xml
<key>NSMicrophoneUsageDescription</key>
<string>Pheme needs microphone access to capture your voice during meetings.</string>
<key>NSSystemAudioCaptureUsageDescription</key>
<string>Pheme needs system audio access to hear other meeting participants.</string>
```

### Runtime Permissions Required
1. **Microphone** — `AVCaptureDevice.requestAccess(for: .audio)`
2. **System Audio** — Core Audio Tap consent (system dialog on first use)

---

## 13. project.yml (XcodeGen)

```yaml
name: Pheme
options:
  bundleIdPrefix: com.sonpiaz
  deploymentTarget:
    macOS: "14.2"
  xcodeVersion: "16.0"

settings:
  base:
    PRODUCT_BUNDLE_IDENTIFIER: com.sonpiaz.pheme
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: 1
    SWIFT_VERSION: "5.9"
    CODE_SIGN_IDENTITY: "-"
    ENABLE_HARDENED_RUNTIME: false
    MACOSX_DEPLOYMENT_TARGET: "14.2"
    INFOPLIST_FILE: Resources/Info.plist
    CODE_SIGN_ENTITLEMENTS: Resources/Pheme.entitlements

targets:
  Pheme:
    type: application
    platform: macOS
    sources:
      - Sources/Pheme
    resources:
      - Resources/Assets.xcassets
      - path: Resources/Info.plist
        buildPhase: none
    settings:
      base:
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

---

## 14. Verification Plan

### Phase 1 Verification
- [ ] `make build` succeeds
- [ ] App launches with empty meeting list
- [ ] Click Record → mic starts capturing (audio level visible)
- [ ] Live transcript appears in Vietnamese within 1-2 seconds
- [ ] Click Stop → recording ends, meeting saved to list
- [ ] Restart app → meeting persists in history
- [ ] Click meeting → view raw transcript

### Phase 2 Verification
- [ ] System audio capture works during Zoom/Meet call
- [ ] "Me" and "Them" segments appear correctly labeled
- [ ] Segments interleaved by timestamp
- [ ] Both audio level meters active

### Phase 3 Verification
- [ ] Summary auto-generates within 5 seconds of stopping
- [ ] Title is relevant to meeting content
- [ ] Summary has correct sections (Key Points, Decisions, Action Items)
- [ ] Summary language matches transcript language
- [ ] "Regenerate" produces new summary
- [ ] "Copy" buttons work

### Phase 4 Verification
- [ ] Meeting list shows date grouping and search
- [ ] Menu bar shows recording state
- [ ] Onboarding works on fresh install
- [ ] Sound feedback plays on start/stop
- [ ] 30+ min recording stable (no memory leak, WebSocket stays connected)
- [ ] Settings persist across restarts

---

## 15. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Core Audio Taps require macOS 14.2+ | Users on 14.0-14.1 excluded | Graceful degrade: mic-only mode on older macOS |
| WebSocket drops during long meetings | Lost transcript segments | Auto-reconnect + local audio buffer (5s) + incremental SwiftData save |
| OpenAI Realtime API cost ($7/hr) | Expensive for heavy users | Offer batch mode ($0.36/hr) in Phase 5 |
| Vietnamese tonal diacritics errors | Incorrect transcription | Custom dictionary support + gpt-4o-transcribe handles tones well |
| Realtime API rate limits | Throttled during peak | Queue audio chunks, don't drop them |
| System audio capture consent UX | Users confused by permission | Clear onboarding explanation + visual guide |
