import CoreGraphics
import Foundation

/// Раскладка экранных кнопок. Координаты — доли экрана, чтобы раскладка подходила и iPhone, и iPad.
struct ControlButton: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case button, toggle, joystick }
    var id = UUID()
    var kind: Kind = .button
    var label: String
    var codes: [Int]
    var x: Double
    var y: Double
    var size: Double = 56
}

struct ControlLayout: Codable {
    var buttons: [ControlButton]

    static let file = Paths.root.appending(path: "controls.json")

    static func load() -> ControlLayout {
        guard let data = try? Data(contentsOf: file),
              let layout = try? JSONDecoder().decode(ControlLayout.self, from: data) else { return .standard }
        return layout
    }

    func save() {
        try? JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
    }

    static let standard = ControlLayout(buttons: [
        ControlButton(kind: .joystick, label: "", codes: [Int(GLFW.key("W")), Int(GLFW.key("A")), Int(GLFW.key("S")), Int(GLFW.key("D"))],
                      x: 0.14, y: 0.72, size: 150),
        ControlButton(label: "⬆︎", codes: [Int(GLFW.space)], x: 0.9, y: 0.75, size: 64),
        ControlButton(kind: .toggle, label: "⇩", codes: [Int(GLFW.leftShift)], x: 0.9, y: 0.92, size: 52),
        ControlButton(kind: .toggle, label: "»", codes: [Int(GLFW.leftControl)], x: 0.14, y: 0.42, size: 46),
        ControlButton(label: "⚔︎", codes: [GLFW.mouseLeftCode], x: 0.78, y: 0.6, size: 56),
        ControlButton(label: "✋", codes: [GLFW.mouseRightCode], x: 0.78, y: 0.82, size: 56),
        ControlButton(label: "E", codes: [Int(GLFW.key("E"))], x: 0.96, y: 0.55, size: 44),
        ControlButton(label: "Q", codes: [Int(GLFW.key("Q"))], x: 0.96, y: 0.42, size: 40),
        ControlButton(label: "⏸", codes: [Int(GLFW.escape)], x: 0.5, y: 0.06, size: 40),
        ControlButton(label: "💬", codes: [Int(GLFW.key("T"))], x: 0.06, y: 0.06, size: 40),
        ControlButton(label: "⌨︎", codes: [GLFW.keyboardCode], x: 0.14, y: 0.06, size: 40),
        ControlButton(label: "F5", codes: [Int(GLFW.f5)], x: 0.58, y: 0.06, size: 40),
        ControlButton(label: "◀︎", codes: [GLFW.scrollUpCode], x: 0.32, y: 0.94, size: 40),
        ControlButton(label: "▶︎", codes: [GLFW.scrollDownCode], x: 0.68, y: 0.94, size: 40),
    ])
}
