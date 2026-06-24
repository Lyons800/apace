import AppKit

enum AppContext: String, CaseIterable, Codable, Sendable {
    case codeEditor
    case email
    case chat
    case document
    case terminal
    case browser
    case other
}

struct ContextDetector {

    private static let bundleIDMap: [String: AppContext] = [
        // Code editors
        "com.microsoft.VSCode": .codeEditor,
        "com.todesktop.230313mzl4w4u92": .codeEditor, // Cursor
        "com.sublimetext.4": .codeEditor,
        "com.sublimetext.3": .codeEditor,
        "com.apple.dt.Xcode": .codeEditor,
        "dev.zed.Zed": .codeEditor,
        "com.jetbrains.intellij": .codeEditor,
        "com.jetbrains.WebStorm": .codeEditor,
        "com.jetbrains.pycharm": .codeEditor,
        "com.jetbrains.CLion": .codeEditor,
        "com.jetbrains.goland": .codeEditor,
        "com.panic.Nova": .codeEditor,
        "com.barebones.bbedit": .codeEditor,

        // Email
        "com.apple.mail": .email,
        "com.microsoft.Outlook": .email,
        "com.readdle.smartemail-macos": .email,
        "com.superhuman.mail": .email,

        // Chat
        "com.tinyspeck.slackmacgap": .chat,
        "com.hnc.Discord": .chat,
        "com.apple.MobileSMS": .chat,
        "ru.keepcoder.Telegram": .chat,
        "net.whatsapp.WhatsApp": .chat,
        "us.zoom.xos": .chat,
        "com.microsoft.teams2": .chat,

        // Terminal
        "com.apple.Terminal": .terminal,
        "com.googlecode.iterm2": .terminal,
        "dev.warp.Warp-Stable": .terminal,
        "net.kovidgoyal.kitty": .terminal,
        "io.alacritty": .terminal,
        "com.mitchellh.ghostty": .terminal,

        // Documents
        "com.apple.iWork.Pages": .document,
        "com.microsoft.Word": .document,
        "com.apple.TextEdit": .document,
        "md.obsidian": .document,
        "notion.id": .document,
        "com.apple.iWork.Keynote": .document,

        // Browsers
        "com.apple.Safari": .browser,
        "com.google.Chrome": .browser,
        "org.mozilla.firefox": .browser,
        "company.thebrowser.Browser": .browser,
        "com.brave.Browser": .browser,
        "com.operasoftware.Opera": .browser,
        "com.vivaldi.Vivaldi": .browser,
    ]

    static func detectContext() -> AppContext {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = frontApp.bundleIdentifier else {
            return .other
        }

        if let context = bundleIDMap[bundleID] {
            return context
        }

        // Fuzzy matching for unknown bundle IDs
        let id = bundleID.lowercased()
        if id.contains("terminal") || id.contains("iterm") || id.contains("warp") || id.contains("kitty") || id.contains("alacritty") {
            return .terminal
        }
        if id.contains("code") || id.contains("editor") || id.contains("ide") || id.contains("vim") {
            return .codeEditor
        }
        if id.contains("mail") || id.contains("outlook") {
            return .email
        }
        if id.contains("slack") || id.contains("discord") || id.contains("telegram") || id.contains("chat") || id.contains("messenger") {
            return .chat
        }

        return .other
    }
}
