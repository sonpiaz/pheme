<p align="center">
  <img src="assets/logo.png" width="120" alt="Pheme">
</p>

<h1 align="center">Pheme</h1>

<p align="center">
  AI meeting notes for macOS — real-time transcript & auto-summary, Vietnamese-optimized.
</p>

<p align="center">
  <a href="https://github.com/sonpiaz/pheme/blob/main/LICENSE"><img src="https://img.shields.io/github/license/sonpiaz/pheme" alt="License" /></a>
  <a href="https://github.com/sonpiaz/pheme/stargazers"><img src="https://img.shields.io/github/stars/sonpiaz/pheme" alt="Stars" /></a>
  <img src="https://img.shields.io/badge/macOS-14.2%2B-black" alt="macOS 14.2+" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9" />
</p>

---

## Features

- **Dual-stream recording** — captures your mic (Me) and system audio (Them) simultaneously
- **Real-time transcript** — live speech-to-text as you speak, not after you finish
- **Auto-generated summaries** — structured notes with key points, decisions, and action items
- **Multi-speaker support** — extensible speaker model (Me, Them, Speaker C, D...) with color-coded pills
- **Vietnamese-first** — optimized for Vietnamese and mixed Vietnamese/English meetings
- **Pause / Resume** — pause recording without ending the meeting
- **Privacy-first** — no bot joins your calls, audio is never stored
- **Menu bar controls** — start, stop, and monitor from the macOS menu bar
- **Search** — full-text search across all meeting titles and transcripts
- **Auto-cleanup** — empty test meetings are purged on launch

<p align="center">
  <img src="assets/demo.png" width="700" alt="Pheme Screenshot">
</p>

## Install

### Homebrew

```bash
brew tap sonpiaz/tap https://github.com/sonpiaz/homebrew-tap
brew install --cask pheme
```

### Build from source

```bash
git clone https://github.com/sonpiaz/pheme.git
cd pheme
brew install xcodegen    # if not installed
make run
```

## Quick Start

1. Launch Pheme
2. Grant microphone permission when prompted
3. Grant Screen Recording permission in System Settings → Privacy & Security
4. Enter your [OpenAI API key](https://platform.openai.com) in Settings (⌘,)
5. Click Record — speak, and watch the transcript appear in real-time

## How It Works

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│  Microphone  │────▶│  AudioChunker │────▶│  RealtimeAPI     │
│  (AVAudio)   │     │  (24kHz PCM)  │     │  (Me transcript) │
└─────────────┘     └──────────────┘     └────────┬────────┘
                                                   │
┌─────────────┐     ┌──────────────┐     ┌─────────▼────────┐
│ System Audio │────▶│  AudioChunker │────▶│  RealtimeAPI     │
│ (CoreAudio)  │     │  (24kHz PCM)  │     │ (Them transcript)│
└─────────────┘     └──────────────┘     └────────┬────────┘
                                                   │
                                          ┌────────▼────────┐
                                          │  GPT-4o-mini     │
                                          │  (Summary Gen)   │
                                          └─────────────────┘
```

**Audio capture** uses AVAudioEngine for mic and Core Audio Taps (`CATapDescription`) for system audio — capturing all other apps without joining your call.

**Transcription** streams PCM16 audio at 24kHz over WebSocket to OpenAI's Realtime Transcription API (`gpt-4o-transcribe`), with server-side VAD for natural turn detection.

**Summaries** are generated via OpenAI Chat Completions (GPT-4o) in the same language as the transcript.

## Requirements

- macOS 14.2+ (Sonoma)
- OpenAI API key
- Microphone permission
- Screen Recording permission (for system audio capture)

## Privacy

Pheme sends audio data **only** to OpenAI for transcription. No audio is stored locally or sent anywhere else. API keys are stored in UserDefaults on your Mac. Meeting transcripts and summaries are stored locally via SwiftData.

## Development

```bash
make generate    # Generate Xcode project
make build       # Build via xcodebuild
make run         # Build and run
make release     # Build release DMG
make clean       # Clean build artifacts
```

## Project Structure

```
Sources/Pheme/
├── App/
│   ├── PhemeApp.swift            — App entry, menu bar, onboarding
│   └── AppState.swift            — Shared state, recent meetings, cleanup
├── Audio/
│   ├── MicRecorder.swift         — 24kHz mono mic capture via AVAudioEngine
│   ├── SystemAudioRecorder.swift — System audio via Core Audio Taps
│   ├── AudioChunker.swift        — Float32 → PCM16LE → base64 chunks
│   └── DualStreamMixer.swift     — Routes mic + system to separate chunkers
├── Transcription/
│   ├── RealtimeTranscriber.swift — WebSocket client for OpenAI Realtime API
│   └── TranscriptionSession.swift — Orchestrates dual-stream transcription
├── Summary/
│   ├── SummaryGenerator.swift    — GPT-4o title + summary generation
│   └── SummaryPrompts.swift      — Bilingual prompt templates
├── Storage/
│   ├── Meeting.swift             — SwiftData model with formatted transcript
│   └── TranscriptSegment.swift   — Speaker enum (Me, Them, multi-speaker)
├── UI/
│   ├── MainContentView.swift     — Split view: list + detail + transcript
│   ├── MeetingListView.swift     — Sidebar with search and date grouping
│   ├── LiveTranscriptView.swift  — Real-time scrolling transcript
│   ├── RecordingControlView.swift — Record/pause/stop buttons
│   ├── MenuBarView.swift         — Menu bar controls
│   ├── SettingsView.swift        — API key, preferences
│   └── OnboardingView.swift      — First-launch permission wizard
└── System/
    ├── SoundFeedback.swift       — Start/stop audio cues
    ├── LaunchAtLogin.swift       — Auto-start at login
    ├── PermissionManager.swift   — Permission checks
    └── CustomDictionary.swift    — User-defined terms for transcription
```

## Tech Stack

| Technology | Purpose |
|-----------|---------|
| [Swift 5.9](https://swift.org/) | Language |
| SwiftUI + SwiftData | UI framework + persistence |
| AVFoundation | Microphone audio capture |
| Core Audio | System audio capture (CATapDescription) |
| OpenAI Realtime API | Live transcription via WebSocket |
| OpenAI Chat Completions | Summary generation (GPT-4o) |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | Project generation |

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Related

- [Kapt](https://github.com/sonpiaz/kapt) — macOS screenshot tool with annotation & OCR
- [Yap](https://github.com/sonpiaz/yap) — Push-to-talk dictation for Mac
- [hidrix-tools](https://github.com/sonpiaz/hidrix-tools) — MCP server for web & social search

## License

MIT — see [LICENSE](LICENSE) for details.

## Why "Pheme"?

Named after [Pheme](https://en.wikipedia.org/wiki/Pheme) (Φήμη) — the Greek goddess of fame, rumor, and voice. She heard everything and spread the word.
