import UIKit

/// Коды клавиш и кнопок мыши GLFW и перевод из HID-кодов iOS.
enum GLFW {
    static let release: Int32 = 0, press: Int32 = 1, repeatAction: Int32 = 2
    static let mouseLeft: Int32 = 0, mouseRight: Int32 = 1, mouseMiddle: Int32 = 2

    static let space: Int32 = 32, escape: Int32 = 256, enter: Int32 = 257, tab: Int32 = 258, backspace: Int32 = 259
    static let right: Int32 = 262, left: Int32 = 263, down: Int32 = 264, up: Int32 = 265
    static let f1: Int32 = 290, f3: Int32 = 292, f5: Int32 = 294
    static let leftShift: Int32 = 340, leftControl: Int32 = 341, leftAlt: Int32 = 342

    static func key(_ c: Character) -> Int32 { Int32(c.asciiValue ?? 0) }

    /// Псевдокоды для раскладки кнопок: отрицательные значения — кнопки мыши и колесо.
    static let mouseLeftCode = -1, mouseRightCode = -2, mouseMiddleCode = -3, scrollUpCode = -4, scrollDownCode = -5,
               keyboardCode = -6

    static func name(_ code: Int) -> String {
        switch code {
        case mouseLeftCode: return "ЛКМ"
        case mouseRightCode: return "ПКМ"
        case mouseMiddleCode: return "СКМ"
        case scrollUpCode: return "Колесо ↑"
        case scrollDownCode: return "Колесо ↓"
        case keyboardCode: return "Клавиатура"
        case Int(space): return "Space"
        case Int(escape): return "Esc"
        case Int(enter): return "Enter"
        case Int(tab): return "Tab"
        case Int(backspace): return "⌫"
        case Int(leftShift): return "Shift"
        case Int(leftControl): return "Ctrl"
        case Int(leftAlt): return "Alt"
        case Int(up): return "↑"
        case Int(down): return "↓"
        case Int(left): return "←"
        case Int(right): return "→"
        case 290...301: return "F\(code - 289)"
        case 32...96: return String(Character(UnicodeScalar(UInt8(code))))
        default: return "#\(code)"
        }
    }

    /// Варианты для редактора раскладки.
    static let bindable: [Int] = [mouseLeftCode, mouseRightCode, mouseMiddleCode, scrollUpCode, scrollDownCode, keyboardCode]
        + [space, escape, enter, tab, backspace, leftShift, leftControl, leftAlt, up, down, left, right].map(Int.init)
        + Array(65...90) + Array(48...57) + Array(290...301)

    static func mods(_ flags: UIKeyModifierFlags) -> Int32 {
        var m: Int32 = 0
        if flags.contains(.shift) { m |= 0x1 }
        if flags.contains(.control) { m |= 0x2 }
        if flags.contains(.alternate) { m |= 0x4 }
        if flags.contains(.command) { m |= 0x8 }
        if flags.contains(.alphaShift) { m |= 0x10 }
        return m
    }

    static func from(hid: UIKeyboardHIDUsage) -> Int32? {
        let code = hid.rawValue
        switch code {
        case 4...29: return Int32(65 + code - 4)          // A–Z
        case 30...38: return Int32(49 + code - 30)        // 1–9
        case 39: return 48                                // 0
        case 58...69: return Int32(290 + code - 58)       // F1–F12
        case 89...97: return Int32(321 + code - 89)       // Num1–Num9
        default: return table[code]
        }
    }

    private static let table: [Int: Int32] = [
        40: enter, 41: escape, 42: backspace, 43: tab, 44: space,
        45: 45, 46: 61, 47: 91, 48: 93, 49: 92, 51: 59, 52: 39, 53: 96, 54: 44, 55: 46, 56: 47,
        57: 280, 70: 283, 71: 281, 72: 284, 73: 260, 74: 268, 75: 266, 76: 261, 77: 269, 78: 267,
        79: right, 80: left, 81: down, 82: up, 83: 282,
        84: 331, 85: 332, 86: 333, 87: 334, 88: 335, 98: 320, 99: 330,
        224: leftControl, 225: leftShift, 226: leftAlt, 227: 343, 228: 345, 229: 344, 230: 346, 231: 347,
    ]
}

/// Удобные обёртки над нативной очередью событий.
enum Input {
    static func key(_ code: Int32, _ pressed: Bool, mods: Int32 = 0) {
        anvil_send_key(code, code, pressed ? GLFW.press : GLFW.release, mods)
    }

    static func mouse(_ button: Int32, _ pressed: Bool) {
        anvil_send_mouse_button(button, pressed ? GLFW.press : GLFW.release, 0)
    }

    /// Нажатие/отпускание по коду из раскладки (клавиша, кнопка мыши или колесо).
    static func binding(_ code: Int, _ pressed: Bool) {
        switch code {
        case GLFW.mouseLeftCode: mouse(GLFW.mouseLeft, pressed)
        case GLFW.mouseRightCode: mouse(GLFW.mouseRight, pressed)
        case GLFW.mouseMiddleCode: mouse(GLFW.mouseMiddle, pressed)
        case GLFW.scrollUpCode: if pressed { anvil_send_scroll(0, 1) }
        case GLFW.scrollDownCode: if pressed { anvil_send_scroll(0, -1) }
        case GLFW.keyboardCode: break
        default: key(Int32(code), pressed)
        }
    }

    static func text(_ string: String) {
        for scalar in string.unicodeScalars {
            if scalar == "\n" {
                key(GLFW.enter, true); key(GLFW.enter, false)
            } else {
                anvil_send_char(scalar.value, 0)
            }
        }
    }
}
