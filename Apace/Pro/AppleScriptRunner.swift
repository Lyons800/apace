import Foundation

struct AppleScriptResult: Equatable {
    let output: String
    let error: String?
    var succeeded: Bool { error == nil }
}

/// Executes AppleScript via `/usr/bin/osascript` out-of-process. The first time a script
/// targets another app, macOS prompts for Automation permission. Output is expected to be
/// small (status/confirmation strings), so reading to end-of-file after termination is fine.
enum AppleScriptRunner {
    static func run(_ script: String) async -> AppleScriptResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<AppleScriptResult, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            process.terminationHandler = { proc in
                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let trimmedOut = out.trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmedErr = err.trimmingCharacters(in: .whitespacesAndNewlines)
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: AppleScriptResult(output: trimmedOut, error: nil))
                } else {
                    continuation.resume(returning: AppleScriptResult(
                        output: trimmedOut,
                        error: trimmedErr.isEmpty ? "osascript exited \(proc.terminationStatus)" : trimmedErr
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: AppleScriptResult(output: "", error: error.localizedDescription))
            }
        }
    }
}
