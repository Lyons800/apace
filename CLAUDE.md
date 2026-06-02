# Sona — Project Conventions

## What is this?
macOS menu bar dictation app (product name **Sona**, domain sona.app). Hold a hotkey, speak, release — text appears in any app. Powered by WhisperKit (on-device, CoreML + Neural Engine). Renamed Whispr → Murmur → **Sona** (the "Murmur" name collided with 7+ other Mac apps).

> **Naming note:** The product/app is **Sona** (`PRODUCT_NAME = Sona`, bundle id `app.sona`), but the Xcode **target, scheme, and Swift module remain "Murmur"** (`PRODUCT_MODULE_NAME = Murmur`). So `@testable import Murmur`, `MurmurApp`, `MurmurConfig`, the `Murmur/` source dir, and `MurmurTests` are all still correct — only the user-facing name/identity changed. The repo is `Lyons800/sona`; the local folder is still `WhisprMacOS`.

## Stack
- Swift 5.10+, macOS 14.0+ (Sonoma)
- SwiftUI (settings, onboarding) + AppKit (menu bar, status item)
- WhisperKit 0.9+ (speech-to-text via CoreML)
- mlx-swift-lm (optional on-device LLM cleanup via MLXLLM)
- Sparkle 2.6+ (auto-updates)
- AVAudioEngine (audio capture)
- CGEvent + NSPasteboard (text insertion)
- NSEvent globalMonitor (global hotkeys)

## Architecture
- Menu bar app (LSUIElement = true, no dock icon)
- Bundle ID: `app.sona`
- Observable AppState drives all UI updates
- Core modules: AudioRecorder, TranscriptionEngine, HotkeyManager, TextInserter, TextPostProcessor, ContextDetector, LLMProcessor, VoiceCommandParser, CustomDictionary, FileTranscriber, MediaController, UpdateManager
- UI: StatusBarController (menu bar), TranscriptionOverlay (floating preview), SettingsView (SwiftUI), FileTranscriptionView
- Two transcription modes: **streaming** (real-time with floating overlay) and **batch** (fallback)
- Context-aware formatting: ContextDetector reads frontmost app bundle ID → AppContext enum → TextPostProcessor adjusts capitalization/punctuation per context
- Optional LLM post-processing: LLMProcessor wraps mlx-swift-lm (MLXLLM) for local inference, guarded by `#if canImport(MLXLLM)`
- Voice commands + Smart Modes: VoiceCommandParser detects trigger phrases and custom user-defined modes, routes to LLMProcessor

## Conventions
- Use async/await everywhere (no completion handlers)
- @Observable macro for state (not ObservableObject)
- Errors: throw, don't return optionals for failable operations
- Prefer value types (structs/enums) over classes except where reference semantics needed
- All audio processing on background queues, UI updates on @MainActor
- SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor — all types default to @MainActor unless explicitly opted out
- Config struct: `MurmurConfig` (type name unchanged; stored as `sona_config` in UserDefaults, legacy fallback `murmur_config`)
- NSLog prefix: `[Sona]`
- App Support path: `~/Library/Application Support/Sona/`

## File Layout
- `Murmur/Core/` — business logic (audio, transcription, hotkeys, text insertion)
- `Murmur/UI/` — SwiftUI views and AppKit controllers
- `Murmur/Models/` — state, config, result types
- `Murmur/Utilities/` — permissions, key codes, sounds
- `Murmur/Resources/` — sound effects

## Key Decisions
- WhisperKit (CoreML) over whisper.cpp — 2-5x faster, 75% less power
- Accessibility API text insertion first, clipboard paste as fallback
- Default model: base.en (142MB, ~500ms for 5s audio)
- Default hotkey: Right Option key
- Streaming mode on by default; batch mode as automatic fallback
- LLM post-processing off by default (requires adding mlx-swift-lm SPM package)
- Context detection via bundle ID map + fuzzy matching — no accessibility API needed
- Sparkle for auto-updates (EdDSA signed appcast)
- Open-core: free on-device dictation; **$39 one-time Pro license** unlocks the AI/agent layer (license provider TBD — Lemon Squeezy / Polar). (Supersedes the old "$29 via Paddle".)

## Enabling LLM Post-Processing
1. In Xcode: File → Add Package Dependencies → `https://github.com/ml-explore/mlx-swift-lm.git`
2. Add the `MLXLLM` and `MLXLMCommon` products to the Murmur target
3. Build — the `#if canImport(MLXLLM)` guards will activate the LLM code
4. Enable in Settings → Features tab → toggle "Enable LLM cleanup"

## Migration
- On first launch the whole data dir is renamed `{Murmur,Whispr}/` → `Sona/` (atomic move — preserves downloaded models, no re-download). See `TranscriptionHistory.migrateLegacyDataDirectory`.
- UserDefaults flags migrated `murmur_*`/`whispr_*` → `sona_*` (no-op across a bundle-id change — user re-onboards once)
- Config falls back `sona_config` → `murmur_config`
