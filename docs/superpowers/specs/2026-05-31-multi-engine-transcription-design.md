# Multi-Engine Transcription — Design Spec

**Date:** 2026-05-31
**Status:** Approved (design), pending implementation plan
**Author:** Oisin Lyons + Claude

## Problem

Murmur's transcription is hard-wired to WhisperKit with `whisper-base.en` as the default. As of 2026 this is a dated choice: on Apple Silicon, NVIDIA **Parakeet TDT 0.6B** (via FluidAudio) delivers ~2% WER vs base.en's ~10%+ *and* is faster/lighter, and Apple's native **SpeechAnalyzer/DictationTranscriber** (macOS 26+) is a strong, zero-bundle on-device option. No single engine wins everywhere: Parakeet is best for English/European, Apple is excellent on macOS 26+ (but has no custom-vocab API and a 43-locale limit), and WhisperKit still owns the 99-language tail and macOS 14–15.

**Goal:** introduce a clean engine abstraction and ship all three engines, with automatic best-fit selection and a manual override, before launch.

## Constraints & context (from current code)

- `TranscriptionResult` is already Murmur's **own domain type** (`Murmur/Models/TranscriptionResult.swift`); `import WhisperKit` appears in exactly one file (`Murmur/Core/TranscriptionEngine.swift`). The return boundary already exists.
- "Streaming" dictation is **app-layer chunked re-transcription** (`MurmurApp.swift` re-calls `transcribe()` on accumulated audio ~every 1.0s), not engine-native streaming. A **batch-shaped** engine interface therefore covers dictation streaming *and* file transcription for all engines.
- `FileTranscriber` already receives the engine by injection, so it benefits automatically.
- `CustomDictionary` and `LLMProcessor` cleanup are **text post-processing**, applied after transcription — already engine-agnostic. Apple's lack of a custom-vocab API does not hurt us.
- Targets macOS 14.0+ (just corrected from an erroneous 26.2). Apple SpeechAnalyzer is therefore `@available`-gated and offered only on macOS 26+.

## Approach

**Protocol + factory**, idiomatic to the codebase. Rejected alternatives: (a) one mega-class with internal `switch`es — unmaintainable across 3 SDKs; (b) fully separate per-engine code paths — duplicates streaming/file logic. Both discard the clean boundary that already exists.

### 1. Engine boundary

```swift
enum EngineID: String, Codable { case whisperKit, parakeet, appleSpeech }

protocol TranscriptionEngineProtocol: AnyObject {
    var identifier: EngineID { get }
    var isModelLoaded: Bool { get }
    func loadModel(progress: ((Double) -> Void)?) async throws
    func transcribe(audioSamples: [Float], language: String, promptText: String?) async throws -> TranscriptionResult
    func unload()
}
```

Batch-shaped; returns the existing `TranscriptionResult`. App-layer streaming and `FileTranscriber` are unchanged because they only call `transcribe(samples:)`.

### 2. Implementations

- **`WhisperKitEngine`** — the current `TranscriptionEngine` renamed and conformed to the protocol. Near-zero behavior change. Role: 99-language fallback + macOS 14–15. `import WhisperKit` confined here.
- **`ParakeetEngine`** — wraps **FluidAudio** (Apache-2.0, SPM). Default for English/European. v1 uses its batch transcribe; FluidAudio's VAD/endpointing is a later enhancement, not in scope for v1.
- **`AppleSpeechEngine`** — wraps **SpeechAnalyzer + DictationTranscriber**, `@available(macOS 26, *)`. v1 adapts its async result stream into a single `TranscriptionResult` to satisfy the batch protocol; native partial-results streaming is a later enhancement. Not offered on macOS < 26.

### 3. Selection, config, migration

- **`EngineSelector`** resolves `(preference, os, language) → concrete engine`. `Automatic` priority:
  1. macOS 26+ **and** language is an Apple-supported locale → `AppleSpeech`
  2. else language is English/European → `Parakeet`
  3. else → `WhisperKit`
- `MurmurConfig` gains `enginePreference: EnginePreference = .automatic` (`.automatic | .whisperKit | .parakeet | .appleSpeech`). `modelName`/`language` retained (model sub-selection still applies to WhisperKit; Parakeet variant selectable later).
- **Migration:** default `.automatic` means existing base.en users transparently move to the auto-selected best engine. No data migration required. (A user who had explicitly chosen a model keeps `modelName`; under `.automatic` the selector may still pick a non-WhisperKit engine — acceptable, and the override exists for those who want to pin WhisperKit.)

### 4. Model management & first-run

- **Small DMG:** no bundled multi-GB models. Download-on-first-use, matching today's WhisperKit flow. FluidAudio downloads Parakeet on first use; Apple uses OS-managed `AssetInventory` (no app-side download). 
- A **`ModelManager`** presents a unified per-engine view (availability, download, progress, disk usage) so Settings is coherent.
- First run under `.automatic` triggers the selected engine's download using the existing progress UI.

### 5. UI (Settings)

- "Transcription" section: **Engine** picker — `Recommended (Automatic)` plus the three engines, each annotated with size / OS / language fit (Apple greyed with "macOS 26+" on older OS). Model sub-picker shown only when relevant.
- This work also **fixes the existing dead-code bug**: `switchModel`/`updateHotkey` currently have zero callers (model/hotkey changes don't apply until restart). The new picker wires Settings → live engine via a bridge (NotificationCenter or shared observable), so changes apply immediately.

### 6. Testing

- Protocol enables a `MockEngine` → app-layer streaming/fallback logic becomes testable for the first time.
- Unit tests for `EngineSelector` across OS/language combinations.
- Per-engine smoke test (load + transcribe a fixed 16 kHz WAV) behind an integration flag.

### 7. Error handling

- Engine load failure (download error, unsupported OS, model missing) surfaces via the existing error state; `EngineSelector` falls back down the priority chain (e.g., Parakeet download fails → offer WhisperKit) rather than hard-failing the user.
- `transcribe` errors keep the existing last-streaming-text fallback in `MurmurApp`.

## Risks / unknowns to resolve during planning

- **FluidAudio** exact API surface, Parakeet model size, and license fit — verify against current docs before coding.
- **SpeechAnalyzer/DictationTranscriber** real API shape and locale list on macOS 26 — verify against current Apple docs.
- These two SDK integrations (and their model UX) are the real cost; the protocol plumbing is small.

## Out of scope (v1)

- Engine-native streaming (Apple volatile results, FluidAudio VAD/endpointing) — later enhancement.
- WhisperKit 0.17 → 1.0 migration (breaking, separate task).
- Per-engine custom-vocabulary APIs (custom dictionary stays as post-processing).

## Success criteria

1. All three engines load and transcribe behind `TranscriptionEngineProtocol`.
2. `Automatic` selects the documented best engine per OS/language; manual override works.
3. Existing users keep working with no data migration; default experience improves (base.en → auto).
4. DMG size not materially increased (no bundled models).
5. Settings engine/model changes apply live (dead `switchModel` bug fixed).
6. `EngineSelector` and app-layer streaming covered by unit tests via `MockEngine`.
