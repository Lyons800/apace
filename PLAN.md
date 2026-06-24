# Apace — Open-Source Voice-to-Text for macOS

> Fast, private, on-device dictation powered by WhisperKit. A modern alternative to Wispr Flow.

---

## Overview

**What**: A macOS menu bar app that transcribes speech to text and inserts it into any application. Hold a hotkey, speak, release — text appears instantly.

**Why**: Wispr Flow is $10/mo and cloud-dependent. Superwhisper is $8/mo. macOS built-in dictation is mediocre. We want something free, fast, private, and open-source.

**Key differentiators over open-wispr**:
- **WhisperKit** (CoreML + Neural Engine) instead of whisper.cpp subprocess — 2-5x faster, 75% less energy
- **Streaming transcription** — see words appear as you speak, not after you stop
- **LLM post-processing** (optional) — fix grammar, punctuation, formatting via local or API model
- **Modern Swift** — async/await, SwiftUI settings, no legacy Carbon APIs

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                    Apace.app                     │
│                  (Menu Bar App)                    │
├─────────────────────────────────────────────────┤
│                                                   │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────┐ │
│  │  HotkeyMgr  │  │  StatusBar   │  │ Settings│ │
│  │  (NSEvent)  │  │  Controller  │  │ (SwiftUI│ │
│  └──────┬──────┘  └──────┬───────┘  │  Window) │ │
│         │                │           └─────────┘ │
│         ▼                ▼                        │
│  ┌─────────────────────────────┐                 │
│  │      TranscriptionEngine    │                 │
│  │  ┌───────────┐ ┌─────────┐ │                 │
│  │  │ AudioRec  │ │WhisperKit│ │                 │
│  │  │(AVAudio)  │ │(CoreML) │ │                 │
│  │  └───────────┘ └─────────┘ │                 │
│  └──────────────┬──────────────┘                 │
│                 │                                 │
│                 ▼                                 │
│  ┌─────────────────────────────┐                 │
│  │     TextPostProcessor       │                 │
│  │  (punctuation, formatting)  │                 │
│  └──────────────┬──────────────┘                 │
│                 │                                 │
│                 ▼                                 │
│  ┌─────────────────────────────┐                 │
│  │       TextInserter          │                 │
│  │  (clipboard + CGEvent)      │                 │
│  └─────────────────────────────┘                 │
│                                                   │
└─────────────────────────────────────────────────┘
```

---

## Tech Stack

| Component | Choice | Why |
|-----------|--------|-----|
| Language | Swift 5.10+ | Native macOS, async/await, best system API access |
| UI Framework | SwiftUI + AppKit | SwiftUI for settings, AppKit for menu bar + status item |
| Speech Engine | WhisperKit 0.9+ | CoreML + Neural Engine, 75% less energy than whisper.cpp |
| Audio Capture | AVAudioEngine | Low-latency, direct buffer access, 16kHz PCM |
| Hotkey | NSEvent globalMonitor | System-wide, no third-party dependency |
| Text Insertion | NSPasteboard + CGEvent | Clipboard paste with keyboard layout awareness |
| Persistence | UserDefaults + JSON | Simple config, no database needed |
| Distribution | Homebrew + DMG | Developer-friendly install |
| Build | Xcode + Swift Package Manager | Standard macOS toolchain |

---

## Phase Plan

### Phase 1: Core Dictation Loop (MVP)
**Goal**: Hold hotkey → speak → release → text appears in active app.

#### 1.1 Project Setup
- [ ] Create Xcode project (macOS App, SwiftUI lifecycle)
- [ ] Configure as menu bar app (LSUIElement = true, no dock icon)
- [ ] Add WhisperKit SPM dependency (`https://github.com/argmaxinc/WhisperKit.git`, from: "0.9.0")
- [ ] Set deployment target: macOS 14.0 (Sonoma) — WhisperKit requirement
- [ ] Add Info.plist keys:
  - `NSMicrophoneUsageDescription`
  - `NSAccessibilityUsageDescription`
- [ ] Add entitlements: Audio Input, Accessibility
- [ ] Set up code signing (Developer ID for distribution)

#### 1.2 Audio Recording (`AudioRecorder.swift`)
- [ ] AVAudioEngine setup with input node tap
- [ ] Convert to PCM Float32, 16kHz mono (WhisperKit requirement)
- [ ] Buffer accumulation for streaming chunks
- [ ] Start/stop recording on hotkey press/release
- [ ] Microphone permission request flow
- [ ] Audio level metering (for UI feedback)

#### 1.3 WhisperKit Integration (`TranscriptionEngine.swift`)
- [ ] Initialize WhisperKit with `base.en` model (default — 142MB, fast)
- [ ] Model download on first launch with progress callback
- [ ] Batch transcription: record → stop → transcribe full audio
- [ ] Handle model loading states (downloading, loading, ready, error)
- [ ] Language configuration (default: English, auto-detect optional)
- [ ] Compute unit configuration (prefer Neural Engine on Apple Silicon)

#### 1.4 Global Hotkey (`HotkeyManager.swift`)
- [ ] NSEvent.addGlobalMonitorForEvents for keyDown/keyUp
- [ ] Default hotkey: Right Option key (less conflict than Globe/Fn)
- [ ] Two modes:
  - **Hold mode** (default): Hold to record, release to transcribe
  - **Toggle mode**: Press to start, press again to stop
- [ ] Visual/audio feedback on activation (subtle sound + menu bar animation)
- [ ] Configurable hotkey via settings

#### 1.5 Text Insertion (`TextInserter.swift`)
- [ ] Save current clipboard contents
- [ ] Place transcribed text on NSPasteboard
- [ ] Simulate Cmd+V via CGEvent (with keyboard layout detection via TIS/UCKeyTranslate)
- [ ] Restore original clipboard after brief delay (200ms)
- [ ] Fallback: CGEvent character-by-character typing for apps that block paste

#### 1.6 Menu Bar UI (`StatusBarController.swift`)
- [ ] NSStatusItem with SF Symbol icon (waveform)
- [ ] State machine: Idle → Recording → Transcribing → Inserting → Idle
- [ ] Recording animation (pulsing dot or waveform)
- [ ] Transcribing animation (bouncing dots)
- [ ] Menu items:
  - Status display (model loaded, hotkey)
  - Start/Stop dictation (manual trigger)
  - Settings...
  - Quit

#### 1.7 App Lifecycle (`ApaceApp.swift`)
- [ ] SwiftUI @main entry with MenuBarExtra
- [ ] Permission checks on launch (mic, accessibility)
- [ ] WhisperKit initialization (background, show progress)
- [ ] Graceful error handling (missing permissions, model download failure)

**Deliverable**: Working dictation — hold Option, speak, release, text appears.

---

### Phase 2: Streaming & Polish
**Goal**: Real-time transcription feedback, better UX.

#### 2.1 Streaming Transcription
- [ ] Switch from batch to `AudioStreamTranscriber`
- [ ] Show interim results in a floating overlay near cursor
- [ ] Confirmed vs unconfirmed segments (visual distinction)
- [ ] Voice Activity Detection (VAD) — auto-stop after silence
- [ ] Configurable silence threshold (default: 0.3)
- [ ] Buffer energy monitoring for UI waveform

#### 2.2 Floating Overlay (`TranscriptionOverlay.swift`)
- [ ] Small floating window near text cursor showing live transcription
- [ ] Follows cursor position (via accessibility API to get caret rect)
- [ ] Semi-transparent, dark background, monospace text
- [ ] Fades in on recording start, fades out after insertion
- [ ] Shows confirmed text in white, unconfirmed in gray

#### 2.3 Model Management
- [ ] Model selector in settings (tiny → large)
- [ ] Download progress with cancel support
- [ ] Automatic model recommendation based on chip (M1 → base, M2+ → small/medium)
- [ ] Model size and expected speed displayed
- [ ] Delete downloaded models to free space

#### 2.4 Sound Effects
- [ ] Subtle activation sound on recording start (like macOS dictation)
- [ ] Completion sound on text insertion
- [ ] Configurable: on/off, volume
- [ ] System sound integration (respects Do Not Disturb)

#### 2.5 Improved Text Post-Processing (`TextPostProcessor.swift`)
- [ ] Capitalize first letter of sentences
- [ ] Convert spoken punctuation ("period" → ".", "comma" → ",", "new line" → "\n")
- [ ] Smart quotes and dashes
- [ ] Remove filler words option ("um", "uh", "like")
- [ ] Trim leading/trailing whitespace and normalize spaces

---

### Phase 3: Intelligence Layer
**Goal**: Context-aware formatting and optional LLM enhancement.

#### 3.1 Context Detection
- [ ] Detect active application (via NSWorkspace)
- [ ] Detect text field type (via Accessibility API — code editor, email, chat, etc.)
- [ ] Adjust behavior per context:
  - Code editors: no auto-capitalization, preserve case
  - Email/docs: full punctuation and formatting
  - Chat apps: casual, no periods at end of messages
  - Terminal: raw text, no modifications

#### 3.2 LLM Post-Processing (Optional)
- [ ] Local model option (MLX-based, runs on-device)
- [ ] Cloud option (OpenAI/Anthropic API for higher quality)
- [ ] Prompt: "Fix grammar, punctuation, and formatting while preserving meaning"
- [ ] Streaming response for low latency
- [ ] Toggle on/off per-app or globally
- [ ] Show original vs corrected in overlay (for transparency)

#### 3.3 Custom Vocabulary
- [ ] User-defined word list for domain-specific terms
- [ ] Auto-correct common misheard words
- [ ] Per-app vocabulary (e.g., code terms for IDE, medical terms for health apps)

---

### Phase 4: Power User Features
**Goal**: Keyboard-centric, deeply configurable.

#### 4.1 Settings Window (SwiftUI)
- [ ] General: Launch at login, show in dock (toggle), notification style
- [ ] Hotkey: Key picker with modifier support, mode (hold/toggle)
- [ ] Model: Selector, download manager, language
- [ ] Audio: Input device selector, noise threshold
- [ ] Text Processing: Punctuation, capitalization, filler removal toggles
- [ ] LLM: Provider, API key, on/off, per-app rules
- [ ] Advanced: Clipboard restore delay, text insertion method

#### 4.2 History
- [ ] Rolling log of last N transcriptions (default: 50)
- [ ] Quick copy from history
- [ ] Searchable
- [ ] Clear history button
- [ ] Optional: save audio recordings (off by default, privacy)

#### 4.3 Multi-Language Support
- [ ] Language selector (or auto-detect)
- [ ] Per-recording language override
- [ ] Multilingual models (non-.en variants)

#### 4.4 Keyboard Shortcuts
- [ ] Cancel recording (Escape while recording)
- [ ] Re-transcribe last recording
- [ ] Toggle LLM processing
- [ ] Open settings

---

### Phase 5: Distribution & Community
**Goal**: Easy install, community contributions.

#### 5.1 Distribution
- [ ] Homebrew Cask formula
- [ ] DMG with drag-to-Applications installer
- [ ] GitHub Releases with universal binary (arm64 + x86_64)
- [ ] Auto-update via Sparkle framework
- [ ] Code signing + notarization for Gatekeeper

#### 5.2 Documentation
- [ ] README with demo GIF
- [ ] Quick start guide
- [ ] Architecture docs for contributors
- [ ] Privacy policy (all processing on-device)

#### 5.3 Open Source
- [ ] MIT License
- [ ] Contributing guide
- [ ] Issue templates
- [ ] CI/CD via GitHub Actions (build + test + notarize)

---

## File Structure

```
apace/
├── Apace.xcodeproj/
├── Apace/
│   ├── ApaceApp.swift              # @main entry, MenuBarExtra
│   ├── AppDelegate.swift            # NSApplicationDelegate for AppKit bridges
│   │
│   ├── Core/
│   │   ├── AudioRecorder.swift      # AVAudioEngine recording
│   │   ├── TranscriptionEngine.swift # WhisperKit wrapper
│   │   ├── TextInserter.swift       # Clipboard + CGEvent paste
│   │   ├── TextPostProcessor.swift  # Punctuation, formatting
│   │   └── HotkeyManager.swift      # Global NSEvent monitor
│   │
│   ├── UI/
│   │   ├── StatusBarController.swift # Menu bar icon + state
│   │   ├── TranscriptionOverlay.swift # Floating live preview
│   │   ├── SettingsView.swift        # SwiftUI settings window
│   │   └── OnboardingView.swift      # First-launch permissions
│   │
│   ├── Models/
│   │   ├── AppState.swift            # Observable app state
│   │   ├── ApaceConfig.swift        # User configuration
│   │   └── TranscriptionResult.swift # Result types
│   │
│   ├── Utilities/
│   │   ├── Permissions.swift         # Mic + accessibility checks
│   │   ├── KeyCodes.swift            # Virtual key code mapping
│   │   └── SoundEffects.swift        # Activation/completion sounds
│   │
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   ├── Sounds/
│   │   └── Info.plist
│   │
│   └── Apace.entitlements
│
├── ApaceTests/
│   ├── TextPostProcessorTests.swift
│   ├── HotkeyManagerTests.swift
│   └── ConfigTests.swift
│
├── Package.swift                     # SPM dependencies (WhisperKit)
├── README.md
├── LICENSE                           # MIT
├── PLAN.md                          # This file
└── CLAUDE.md                        # Project conventions
```

---

## Key Technical Decisions

### Why WhisperKit over whisper.cpp?
| | WhisperKit | whisper.cpp |
|---|---|---|
| Runtime | CoreML + Neural Engine | Metal GPU |
| Cold start | ~1s (cached model) | ~2-3s |
| Latency (base.en) | ~0.5s for 5s audio | ~1.5s for 5s audio |
| Energy | 0.3W (Neural Engine) | 1.5W (GPU) |
| Integration | Native Swift API | Subprocess or C FFI |
| Streaming | Built-in AudioStreamTranscriber | Manual implementation |
| Model format | CoreML (.mlmodelc) | GGML (.bin) |

### Why clipboard paste over accessibility text insertion?
- Works in 99% of apps without special handling
- No per-app fragility (accessibility elements vary wildly)
- Keyboard layout aware (UCKeyTranslate for non-QWERTY)
- Fast and predictable
- Clipboard save/restore minimizes user impact

### Why menu bar app (not dock app)?
- Always accessible, never in the way
- Dictation tools should be invisible until needed
- Matches Wispr Flow, Superwhisper, macOS dictation UX
- LSUIElement = true means no dock icon, no Cmd+Tab entry

---

## Performance Targets

| Metric | Target | Notes |
|--------|--------|-------|
| Recording → first word | < 300ms | Streaming mode |
| Full transcription (5s audio) | < 800ms | base.en model |
| Text insertion latency | < 100ms | Clipboard + paste |
| Memory (idle) | < 50MB | Model unloaded after timeout |
| Memory (active) | < 300MB | base.en model loaded |
| Battery impact | < 1% per hour active use | Neural Engine efficiency |
| Model download | ~142MB | base.en, one-time |
| App size | < 15MB | Without bundled model |

---

## Models Quick Reference

| Model | Size | Speed (5s audio) | Quality | Best For |
|-------|------|-------------------|---------|----------|
| tiny.en | 75MB | ~200ms | Fair | Fastest possible, simple dictation |
| base.en | 142MB | ~500ms | Good | **Default — best speed/quality balance** |
| small.en | 466MB | ~1.2s | Very Good | Higher accuracy, M2+ recommended |
| medium.en | 1.5GB | ~3s | Excellent | Professional use, M2 Pro+ |
| large-v3 | 3GB | ~6s | Best | Maximum accuracy, M3+ recommended |

---

## Build & Run

```bash
# Clone
git clone https://github.com/yourusername/apace.git
cd apace

# Open in Xcode
open Apace.xcodeproj

# Build & Run (Cmd+R)
# First launch will download the base.en model (~142MB)
```

---

## Implementation Order (Phase 1)

Start with the minimal loop and expand:

1. **Project scaffold** — Xcode project, SPM deps, entitlements
2. **AppState** — Observable state machine (idle/recording/transcribing/inserting)
3. **AudioRecorder** — AVAudioEngine, 16kHz PCM capture
4. **TranscriptionEngine** — WhisperKit init, batch transcribe
5. **TextInserter** — Clipboard paste with layout detection
6. **HotkeyManager** — Global key monitor, hold-to-record
7. **StatusBarController** — Menu bar icon, state animations
8. **ApaceApp** — Wire everything together
9. **Permissions** — Onboarding flow for mic + accessibility
10. **TextPostProcessor** — Basic punctuation and capitalization
