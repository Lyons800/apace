import Carbon.HIToolbox
import AppKit

enum KeyCodes {
    static let nameToCode: [String: UInt16] = [
        "a": UInt16(kVK_ANSI_A),
        "b": UInt16(kVK_ANSI_B),
        "c": UInt16(kVK_ANSI_C),
        "d": UInt16(kVK_ANSI_D),
        "e": UInt16(kVK_ANSI_E),
        "f": UInt16(kVK_ANSI_F),
        "g": UInt16(kVK_ANSI_G),
        "h": UInt16(kVK_ANSI_H),
        "i": UInt16(kVK_ANSI_I),
        "j": UInt16(kVK_ANSI_J),
        "k": UInt16(kVK_ANSI_K),
        "l": UInt16(kVK_ANSI_L),
        "m": UInt16(kVK_ANSI_M),
        "n": UInt16(kVK_ANSI_N),
        "o": UInt16(kVK_ANSI_O),
        "p": UInt16(kVK_ANSI_P),
        "q": UInt16(kVK_ANSI_Q),
        "r": UInt16(kVK_ANSI_R),
        "s": UInt16(kVK_ANSI_S),
        "t": UInt16(kVK_ANSI_T),
        "u": UInt16(kVK_ANSI_U),
        "v": UInt16(kVK_ANSI_V),
        "w": UInt16(kVK_ANSI_W),
        "x": UInt16(kVK_ANSI_X),
        "y": UInt16(kVK_ANSI_Y),
        "z": UInt16(kVK_ANSI_Z),
        "space": UInt16(kVK_Space),
        "return": UInt16(kVK_Return),
        "tab": UInt16(kVK_Tab),
        "escape": UInt16(kVK_Escape),
        "delete": UInt16(kVK_Delete),
        "rightOption": UInt16(kVK_RightOption),
        "leftOption": UInt16(kVK_Option),
        "rightCommand": UInt16(kVK_RightCommand),
        "leftCommand": UInt16(kVK_Command),
        "rightShift": UInt16(kVK_RightShift),
        "leftShift": UInt16(kVK_Shift),
        "rightControl": UInt16(kVK_RightControl),
        "leftControl": UInt16(kVK_Control),
        "f1": UInt16(kVK_F1),
        "f2": UInt16(kVK_F2),
        "f3": UInt16(kVK_F3),
        "f4": UInt16(kVK_F4),
        "f5": UInt16(kVK_F5),
        "f6": UInt16(kVK_F6),
        "f7": UInt16(kVK_F7),
        "f8": UInt16(kVK_F8),
        "f9": UInt16(kVK_F9),
        "f10": UInt16(kVK_F10),
        "f11": UInt16(kVK_F11),
        "f12": UInt16(kVK_F12),
    ]

    static let codeToName: [UInt16: String] = {
        Dictionary(nameToCode.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
    }()

    static func displayName(keyCode: UInt16, modifiers: UInt = 0) -> String {
        var parts: [String] = []
        if modifiers & UInt(NSEvent.ModifierFlags.control.rawValue) != 0 { parts.append("^") }
        if modifiers & UInt(NSEvent.ModifierFlags.option.rawValue) != 0 { parts.append("\u{2325}") }
        if modifiers & UInt(NSEvent.ModifierFlags.shift.rawValue) != 0 { parts.append("\u{21E7}") }
        if modifiers & UInt(NSEvent.ModifierFlags.command.rawValue) != 0 { parts.append("\u{2318}") }

        let keyName = codeToName[keyCode]?.capitalized ?? "Key \(keyCode)"
        parts.append(keyName)
        return parts.joined()
    }
}
