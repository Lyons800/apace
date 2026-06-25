import SwiftUI
import AppKit
import DynamicNotchKit

/// The Apace "Dynamic Island" — backed by DynamicNotchKit, which provides the
/// native notch-hugging chrome and expand/collapse animation. We supply the content,
/// driven reactively by `IslandModel`. It hosts both the Pro/AI command layer AND
/// live dictation (the running transcript follows your current word in the notch).

@Observable
final class IslandModel {
    enum Phase: Equatable {
        case hidden
        case listening
        case transcribing(String)   // live dictation transcript, follows the current word
        case thinking
        case running(String)        // an action is executing (e.g. "Creating note…")
        case confirm(summary: String)                                   // risky action — ask first
        case answer(String)                                             // spoken answer
        case done(String)                                               // "did X ✓"
        case result(instruction: String, before: String, after: String) // voice-edit before→after
        case message(String)
    }
    var phase: Phase = .hidden
    var level: Float = 0
    /// True when DynamicNotchKit will use its floating (no-notch) style — e.g. on an
    /// external display in clamshell. There it draws a gray `.popover` material, so
    /// we paint our own solid black behind the content to match the real notch.
    var isFloating = false
}

@MainActor
final class IslandController {
    let model = IslandModel()
    var onUndo: (() -> Void)?
    var onRun: (() -> Void)?
    var onCancel: (() -> Void)?

    private var dismissTask: Task<Void, Never>?

    private lazy var notch: DynamicNotch<IslandView, EmptyView, EmptyView> = {
        let model = self.model
        return DynamicNotch(hoverBehavior: [.keepVisible], style: .auto) { [weak self] in
            IslandView(
                model: model,
                onUndo: { self?.onUndo?(); self?.dismiss() },
                onRun: { self?.onRun?() },
                onCancel: { self?.onCancel?(); self?.dismiss() }
            )
        }
    }()

    func listening() { present(.listening) }

    /// Live dictation: expand the notch on the first tick, then just swap the text
    /// on subsequent ticks so we don't replay the expand animation every second.
    func transcribing(_ text: String) {
        dismissTask?.cancel()
        if case .transcribing = model.phase {
            model.phase = .transcribing(text)   // already shown — update content only
        } else {
            present(.transcribing(text))        // first tick — expand the notch
        }
    }

    func thinking() { present(.thinking) }
    func running(_ text: String) { present(.running(text)) }                            // executing an action
    func confirm(summary: String) { present(.confirm(summary: summary)) }              // no auto-dismiss
    func answer(_ text: String) { present(.answer(text), autoDismiss: 9) }
    func done(_ text: String) { present(.done(text), autoDismiss: 4) }
    func message(_ text: String) { present(.message(text), autoDismiss: 6) }
    func showResult(instruction: String, before: String, after: String) {
        present(.result(instruction: instruction, before: before, after: after), autoDismiss: 7)
    }

    func updateLevel(_ level: Float) { model.level = level }

    func dismiss() {
        dismissTask?.cancel()
        Task { @MainActor in
            await notch.hide()
            model.phase = .hidden
        }
    }

    private func present(_ phase: IslandModel.Phase, autoDismiss seconds: Double? = nil) {
        dismissTask?.cancel()
        model.isFloating = Self.usesFloatingStyle()
        model.phase = phase
        Task { @MainActor in await notch.expand() }
        if let seconds { scheduleDismiss(after: seconds) }
    }

    /// The library renders on `NSScreen.screens[0]` and uses its floating (no-notch)
    /// style when that screen has no notch — mirror that test so we know when to paint
    /// over its gray material.
    private static func usesFloatingStyle() -> Bool {
        (NSScreen.screens.first?.safeAreaInsets.top ?? 0) <= 0
    }

    private func scheduleDismiss(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { self?.dismiss() }
        }
    }
}

// MARK: - View

private let signal = Color(red: 1.0, green: 0.48, blue: 0.16)

struct IslandView: View {
    let model: IslandModel
    let onUndo: () -> Void
    let onRun: () -> Void
    let onCancel: () -> Void

    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: 480, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                // On a no-notch (floating) screen the library shows a gray `.popover`
                // material; paint solid black over it, bleeding past its 15pt safe-area
                // insets so the whole pill is black. On a real notch this is skipped
                // (the notch chrome is already black).
                if model.isFloating { Color.black.padding(-16) }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .listening:
            HStack(spacing: 12) {
                EqBars(level: model.level)
                Text("Listening for a command…").foregroundStyle(.white.opacity(0.85))
            }
            .font(.system(size: 14, weight: .medium))
        case let .transcribing(text):
            TranscribingView(level: model.level, text: text)
        case .thinking:
            HStack(spacing: 12) {
                ProgressView().scaleEffect(0.6).tint(signal)
                Text("Working…").foregroundStyle(.white.opacity(0.85))
            }
            .font(.system(size: 14, weight: .medium))
        case let .running(text):
            HStack(spacing: 12) {
                ProgressView().scaleEffect(0.6).tint(signal)
                Text(text)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 14, weight: .medium))
        case let .confirm(summary):
            confirmView(summary: summary)
        case let .answer(text):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(signal).font(.system(size: 12)).padding(.top, 2)
                ScrollView {
                    Text(text)
                        .foregroundStyle(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 320)
            }
            .font(.system(size: 14, weight: .medium))
        case let .done(text):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(signal)
                Text(text).foregroundStyle(.white.opacity(0.95)).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 14, weight: .medium))
        case let .result(instruction, before, after):
            resultView(instruction: instruction, before: before, after: after)
        case let .message(text):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(signal)
                    .font(.system(size: 13))
                    .padding(.top, 1)
                Text(text).foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 14, weight: .medium))
        }
    }

    private func confirmView(summary: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ABOUT TO")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(signal.opacity(0.9))
                Text(summary)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.12)))
            }.buttonStyle(.plain)
            Button(action: onRun) {
                Text("Run")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color(red: 0.1, green: 0.06, blue: 0.02))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(signal))
            }.buttonStyle(.plain)
        }
    }

    private func resultView(instruction: String, before: String, after: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars").foregroundStyle(signal).font(.system(size: 11))
                Text(instruction.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(signal.opacity(0.9))
                    .lineLimit(1)
                Spacer()
                Button(action: onUndo) {
                    Text("Undo")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }.buttonStyle(.plain)
            }
            Text(before)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .strikethrough(color: .white.opacity(0.25))
                .lineLimit(3)
            Text(after)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Live dictation transcript in the notch. FIXED width and height — the consensus
/// pattern across DynamicNotchKit (`InfoView` is `.frame(height: 40)`) and
/// TheBoringNotch. Grow-to-fit is exactly what made the box jitter between 1 and 2
/// lines as live words flickered. Text fills a stable 2-line box and scrolls,
/// auto-pinned to the bottom so the newest words stay visible.
private struct TranscribingView: View {
    let level: Float
    let text: String

    /// Show only the most recent slice so the current word is always visible. A
    /// ScrollView inside DynamicNotchKit doesn't reliably auto-pin to the bottom, so
    /// we window the text + head-truncate instead — deterministic, always-latest.
    private var windowed: String {
        let maxChars = 180
        guard text.count > maxChars else { return text }
        let tail = text.suffix(maxChars)
        if let sp = tail.firstIndex(of: " ") { return "…" + tail[tail.index(after: sp)...] }
        return "…" + tail
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {          // centered, fixed-height row
            EqBars(level: level)
            Text(text.isEmpty ? "Listening…" : windowed)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(text.isEmpty ? .white.opacity(0.6) : .white.opacity(0.95))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .truncationMode(.head)                     // keep the END (latest words) visible
                .frame(width: 300, height: 34, alignment: .bottomLeading)
        }
    }
}

private struct EqBars: View {
    let level: Float

    /// Speech RMS lands around 0.001–0.05 — far below a linear bar threshold, which is
    /// why the bars sat frozen. Map it logarithmically (0.001→0, ~0.3→1), same as the
    /// cursor overlay's waveform, so quiet speech still drives visible motion.
    private var norm: CGFloat {
        let clamped = max(Float(0.0008), min(level, 0.3))
        let logVal = (log10(clamped) + 3.1) / 2.6      // 0.0008→0, 0.3→~1
        return CGFloat(max(0, min(logVal, 1)))
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                let h = max(0.12, norm * (0.45 + 0.55 * abs(sin(Double(i) * 1.3))))
                RoundedRectangle(cornerRadius: 2)
                    .fill(signal)
                    .frame(width: 3, height: 5 + h * 18)
                    .animation(.interpolatingSpring(stiffness: 300, damping: 11), value: norm)
            }
        }
        .frame(height: 22)
    }
}
