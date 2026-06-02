import SwiftUI

struct OnboardingView: View {
    @State private var hasMic = Permissions.checkMicrophone()
    @State private var hasAccessibility = Permissions.checkAccessibility()
    @State private var pollTask: Task<Void, Never>?
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to Sona")
                .font(.title)
                .fontWeight(.semibold)

            Text("Fast, private, on-device dictation.\nHold a key, speak, release — text appears.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Required — records your voice for transcription",
                    granted: hasMic,
                    buttonLabel: "Grant",
                    action: {
                        let granted = await Permissions.requestMicrophone()
                        hasMic = granted
                        if !granted {
                            // User was sent to System Settings — poll for change
                            startMicPolling()
                        }
                    }
                )

                permissionRow(
                    icon: "lock.open.fill",
                    title: "Accessibility",
                    description: "Optional — auto-pastes text into apps. Without it, text is copied to clipboard.",
                    granted: hasAccessibility,
                    buttonLabel: "Grant",
                    action: {
                        _ = Permissions.requestAccessibility()
                        startAccessibilityPolling()
                    }
                )
            }
            .padding(.horizontal)

            Button(action: {
                pollTask?.cancel()
                onComplete()
            }) {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasMic)

            if !hasMic {
                Text("Microphone access is required to use Sona.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !hasAccessibility {
                Text("You can grant Accessibility later in Settings. Text will be copied to clipboard until then.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(width: 420)
        .onDisappear {
            pollTask?.cancel()
        }
    }

    private func startMicPolling() {
        pollTask?.cancel()
        pollTask = Task {
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if Permissions.checkMicrophone() {
                    hasMic = true
                    return
                }
            }
        }
    }
 
    private func startAccessibilityPolling() {
        pollTask?.cancel()
        pollTask = Task {
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if Permissions.checkAccessibility() {
                    hasAccessibility = true
                    return
                }
            }
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        buttonLabel: String = "Grant",
        action: @escaping () async -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 32)
                .foregroundStyle(granted ? .green : .secondary)

            VStack(alignment: .leading) {
                Text(title).fontWeight(.medium)
                Text(description).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(buttonLabel) {
                    Task { await action() }
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
