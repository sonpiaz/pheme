# Pheme

> Vietnamese-optimized AI meeting notes for macOS.
> Named after Pheme (Phi-me) — Greek goddess of voice and speech.

Pheme captures meeting audio (mic + system audio), shows real-time transcript, and auto-generates structured summaries — optimized for Vietnamese + English mixed language.

## Features

- **Dual-stream recording** — captures your mic (Me) and system audio (Them) simultaneously via Core Audio Taps
- **Real-time transcript** — live speech-to-text using OpenAI `gpt-4o-transcribe` Realtime API over WebSocket
- **Auto-generated summaries** — structured meeting notes (key points, decisions, action items) via GPT-4o-mini
- **Vietnamese-first** — optimized for Vietnamese and mixed Vietnamese/English meetings
- **Pause/Resume** — pause recording without ending the meeting
- **Privacy-first** — no bot joins your calls, audio is not stored
- **Menu bar controls** — quick access from the macOS menu bar
- **Search** — search across all meeting titles and transcripts

## Requirements

- macOS 14.2+ (Sonoma)
- OpenAI API key
- Microphone permission
- Screen Recording permission (for system audio capture)

## Tech Stack

- Swift 5.9, SwiftUI, SwiftData
- OpenAI Realtime Transcription API (WebSocket, PCM16 24kHz)
- OpenAI Chat Completions API (GPT-4o-mini for summaries)
- Core Audio Taps (`CATapDescription`) for system audio
- AVAudioEngine for microphone capture
- XcodeGen for project generation

## Project Structure

```
Sources/Pheme/
├── App/                  # PhemeApp entry, AppState
├── Audio/                # MicRecorder, SystemAudioRecorder, DualStreamMixer, AudioChunker
├── Transcription/        # RealtimeTranscriber (WebSocket), TranscriptionSession
├── Summary/              # SummaryGenerator, SummaryPrompts
├── Storage/              # SwiftData models (Meeting, TranscriptSegment)
├── UI/                   # SwiftUI views (MainContent, MeetingList, RecordingControl, etc.)
└── System/               # SoundFeedback, LaunchAtLogin, CustomDictionary, PermissionManager
```

## Build & Run

```bash
# Generate Xcode project
make generate

# Build
make build

# Run
make run
```

Or open `Pheme.xcodeproj` in Xcode directly.

## Setup

1. Launch Pheme
2. Grant microphone permission when prompted
3. Grant Screen Recording permission in System Settings (for system audio)
4. Enter your OpenAI API key in Settings

## License

Private — All rights reserved.
