# Apace — Product & Monetization Roadmap

_Last updated: 2026-05-31_

## 1. Positioning (the one-liner)

**Apace transcribes for free. Apace Pro is your voice-powered AI — it edits, learns, commands, and controls your Mac.**

The competitive research (2026) is unambiguous: raw transcription is **commoditized** (Parakeet is CC-BY, WhisperKit MIT, Apple SpeechAnalyzer free, Ollama cleanup free), and free open-source rivals already replicate Apace's exact engine stack (macparakeet, Handy ~22.8k★, FluidVoice). Meanwhile the category is moving **dictation → on-device AI editing → voice agent**. So Apace's defensible value lives **up the stack**, not in the engine.

Strategy: **open-core.** Give away the commoditized transcription core (free + open-source → trust, adoption, neutralizes OSS rivals). Charge a **one-time license** for the AI/agent layer (genuinely hard, on-trend, Apple/OSS won't build it).

## 2. Monetization model

- **Open-core**, **one-time license** (no subscription — leans into the anti-subscription wedge the entire market hates).
- Cloud-heavy features (screen reasoning in Command Mode) use **BYOK** (user's own Claude/OpenAI key) so Apace never eats per-use cloud costs and the one-time model stays sustainable.
- Optional later: a managed-cloud credits/subscription add-on for non-technical users who won't bring an API key. Not v1.

### Free vs Pro split

| | **Apace (Free, open-source)** | **Apace Pro (one-time license)** |
|---|---|---|
| Transcription — 3 engines (Parakeet/Apple/WhisperKit), auto-select + override | ✅ | ✅ |
| Hotkey dictation, streaming overlay, history | ✅ | ✅ |
| AI cleanup (filler removal, punctuation, capitalization, basic formatting) | ✅ | ✅ |
| Per-app context formatting, custom dictionary (manual), file transcription | ✅ | ✅ |
| **Command Mode** — screen-aware voice (see screen, answer, act) | — | ✅ |
| **Voice-edit selected text** ("rephrase / make a list / more formal / translate") | — | ✅ |
| **Auto-learning vocabulary + writing style** | — | ✅ |
| **Voice-to-action** (Shortcuts / AppleScript / MCP / open apps) | — | ✅ |
| Advanced AI transforms (tone presets, summarize, custom prompts/modes) | — | ✅ |

**The line:** "speak → clean text" is free; "the AI reasons / edits / acts" is Pro.

### Pricing (proposal)
- **Apace Pro: $39 one-time** (lifetime, 2 Macs). Anchors above VoiceInk ($25) and below MacWhisper (€59); undercuts every subscription's first-year cost ($84–180/yr). BYOK for Command Mode.
- Optional later: $49 "Extended" (more Macs) and/or managed-cloud credits.

## 3. Command Mode — the headline Pro feature (Clicky-inspired)

Reference: **Clicky** by Farza (open-source) — hold Control+Option, it screenshots the screen + captures voice, sends to Claude, and responds (even points at things). https://github.com/farzaa/clicky

Apace's version, on-brand (privacy-first, on-device-where-possible + BYOK):

- **Hotkey:** `Option` = transcribe (today). **`Option+Shift`** (configurable) = **Command Mode**.
- **Flow:** on activation → capture the active screen (or selection) + listen → route to an AI that *sees the screen* → respond inline / speak / act.
- **Privacy posture:** prefer on-device (Apple/local LLM) for text-only commands; use **BYOK cloud** (Claude/GPT-4o-vision) only when screen-vision reasoning is needed, with an explicit indicator that a screenshot is being sent. Never silent.
- **v1 (answer/transform):** "what's on screen / explain this / rewrite the selection / summarize this." Reuses the on-device LLM + Accessibility API; screen-vision via BYOK.
- **v2 (act):** voice-to-action — run a Shortcut, open an app, fill a field, AppleScript bridge, MCP tool-calling. Bounded + on-device-first.

This is the feature that turns Apace from "a dictation app" into "a voice interface to your Mac" — the differentiator vs every transcription competitor.

## 4. Roadmap (sequenced)

**Phase 0 — Launch hygiene (now → 2 weeks)**
- ✅ v1.0.0 shipped (notarized DMG, public).
- Fix CI for automated releases (`macos-26` runner + Xcode 26; appcast duplicate-`length`; Sparkle 2.9.x); generate `appcast.xml` so auto-update works.
- Resolve brand collision (multiple apps named "Apace") + pick the real domain.
- Ship the landing-page overhaul reflecting open-core + Pro.

**Phase 1 — Open-core foundation (weeks 2–4)**
- **Open-source the free core** (license: MIT or GPLv3 — decide; GPLv3 protects against closed forks, MIT maximizes adoption). Split the repo: open `apace-core` (transcription) vs closed Pro module, OR single repo with Pro features behind a license gate.
- **License gating** + payment: Gumroad / Lemon Squeezy / Paddle license keys; a `ProEntitlement` check that unlocks Pro features. (No account required — offline license validation.)
- **"Verifiably on-device" trust kit** — airplane-mode-works badge, zero-network claim, optional network-audit writeup. Cheap, high-trust, on-brand.

**Phase 2 — The AI layer (Pro v1) (weeks 4–8)**
- **Voice-edit selected text** (#1 competitive gap; reuse on-device LLM + Accessibility API to read/replace selection). Medium effort, highest leverage.
- **Auto-learning vocabulary + style** (passively add repeated proper nouns / corrections; on-device).
- **Advanced AI transforms** (tone/format presets, summarize, translate via on-device MT where feasible, custom prompt "modes").

**Phase 3 — Command Mode (Pro v2) (weeks 8–14)**
- Command Mode v1 (screen-aware answer/transform, `Option+Shift`, BYOK vision).
- Command Mode v2 (voice-to-action: Shortcuts/AppleScript/MCP).

**Phase 4 — Distribution (parallel/after)**
- iOS companion (SpeechAnalyzer is on-device on iOS 26) — biggest reach bet.
- Raycast extension / editor integrations.
- Privacy-preserving settings/dictionary sync (opt-in, local-first) — only if iOS ships.

## 5. The competitive gaps this closes (from 2026 research)

1. Closed-source flank → **open the core** (Phase 1).
2. No NL editing of existing text → **voice-edit selected text** (Phase 2).
3. Manual dictionary → **auto-learning vocab** (Phase 2).
4. No agentic voice-to-action → **Command Mode** (Phase 3).
5. Mac-only / no sync → **iOS + sync** (Phase 4).

## 6. Risks & watch-items

- **Apple eats the base layer** — SpeechAnalyzer improves each release. Mitigation: differentiation lives in the AI/agent layer, not the engine.
- **Open-sourcing cannibalization** — someone forks the free core. Mitigation: the value (and license gate) is the Pro AI layer; GPLv3 deters closed forks; brand + polish + Pro cadence stay ahead.
- **BYOK friction** — non-technical users won't bring an API key. Mitigation: managed-cloud credits as a later add-on; keep on-device path for everything that doesn't need vision.
- **Brand collision** — multiple "Apace" apps muddy search. Resolve domain + naming early.
- **License-key piracy** — accept some leakage (one-time indie norm); keep validation offline/simple; convert on value + updates.
