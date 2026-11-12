import UIKit

/// Слой экранных кнопок. Пустые места пропускают касания к поверхности игры (там работает камера).
final class ControlsOverlay: UIView {
    var layout = ControlLayout.load() { didSet { rebuild() } }
    var onKeyboard: (() -> Void)?
    var isEditing = false { didSet { controls.forEach { $0.isEditing = isEditing } } }

    private var controls: [ControlView] { subviews.compactMap { $0 as? ControlView } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        controls.forEach { $0.place(in: bounds) }
    }

    func rebuild() {
        controls.forEach { $0.removeFromSuperview() }
        for model in layout.buttons {
            let view: ControlView = model.kind == .joystick ? JoystickView(model: model) : ButtonView(model: model)
            view.overlay = self
            view.isEditing = isEditing
            addSubview(view)
        }
        setNeedsLayout()
    }

    func update(_ model: ControlButton) {
        if let i = layout.buttons.firstIndex(where: { $0.id == model.id }) { layout.buttons[i] = model }
        layout.save()
    }

    func remove(_ model: ControlButton) {
        layout.buttons.removeAll { $0.id == model.id }
        layout.save()
    }

    func addButton() {
        layout.buttons.append(ControlButton(label: "?", codes: [Int(GLFW.key("F"))], x: 0.5, y: 0.5))
        layout.save()
    }

    /// Отпускает всё, что зажато (например, при сворачивании приложения).
    func releaseAll() { controls.forEach { $0.reset() } }
}

class ControlView: UIView {
    var model: ControlButton
    weak var overlay: ControlsOverlay?
    var isEditing = false { didSet { reset(); layer.borderColor = (isEditing ? UIColor.systemYellow : UIColor.white).cgColor } }
    private var dragOffset = CGPoint.zero

    init(model: ControlButton) {
        self.model = model
        super.init(frame: CGRect(x: 0, y: 0, width: model.size, height: model.size))
        alpha = AppSettings.shared.controlsOpacity
        layer.cornerRadius = model.size / 2
        layer.borderWidth = 1.5
        layer.borderColor = UIColor.white.cgColor
        backgroundColor = UIColor(white: 0.1, alpha: 0.55)
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    func place(in bounds: CGRect) {
        center = CGPoint(x: bounds.width * model.x, y: bounds.height * model.y)
    }

    func reset() {}
    func began(_ point: CGPoint) {}
    func moved(_ point: CGPoint) {}
    func ended() {}

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if isEditing {
            let p = touch.location(in: superview)
            dragOffset = CGPoint(x: center.x - p.x, y: center.y - p.y)
        } else {
            began(touch.location(in: self))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let superview else { return }
        if isEditing {
            let p = touch.location(in: superview)
            center = CGPoint(x: p.x + dragOffset.x, y: p.y + dragOffset.y)
            model.x = Double(center.x / superview.bounds.width)
            model.y = Double(center.y / superview.bounds.height)
        } else {
            moved(touch.location(in: self))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isEditing { overlay?.update(model) } else { ended() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}

final class ButtonView: ControlView {
    private let label = UILabel()
    private var isOn = false

    override init(model: ControlButton) {
        super.init(model: model)
        label.text = model.label
        label.textColor = .white
        label.textAlignment = .center
        label.font = .systemFont(ofSize: model.size * 0.38, weight: .semibold)
        label.adjustsFontSizeToFitWidth = true
        label.frame = bounds.insetBy(dx: 4, dy: 4)
        addSubview(label)
        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    private func send(_ pressed: Bool) {
        model.codes.forEach { Input.binding($0, pressed) }
        backgroundColor = UIColor(white: pressed ? 0.6 : 0.1, alpha: 0.55)
    }

    override func began(_ point: CGPoint) {
        if model.codes.contains(GLFW.keyboardCode) { overlay?.onKeyboard?(); return }
        if model.kind == .toggle {
            isOn.toggle()
            send(isOn)
        } else {
            send(true)
        }
    }

    override func ended() {
        if model.kind == .button { send(false) }
    }

    override func reset() {
        if isOn { isOn = false; send(false) }
    }
}

extension ButtonView: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard isEditing else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            guard let self else { return nil }
            let bindings = GLFW.bindable.map { code in
                UIAction(title: GLFW.name(code), state: self.model.codes == [code] ? .on : .off) { _ in
                    self.model.codes = [code]
                    self.model.label = GLFW.name(code)
                    self.commit()
                }
            }
            let sizes = [40.0, 48, 56, 64, 80].map { size in
                UIAction(title: "\(Int(size)) pt", state: self.model.size == size ? .on : .off) { _ in
                    self.model.size = size
                    self.commit()
                }
            }
            return UIMenu(children: [
                UIMenu(title: "Назначение", children: bindings),
                UIMenu(title: "Размер", children: sizes),
                UIAction(title: self.model.kind == .toggle ? "Сделать обычной" : "Сделать переключателем") { _ in
                    self.model.kind = self.model.kind == .toggle ? .button : .toggle
                    self.commit()
                },
                UIAction(title: "Удалить", attributes: .destructive) { _ in
                    self.overlay?.remove(self.model)
                },
            ])
        })
    }

    private func commit() { overlay?.update(model) }
}

/// Джойстик WASD. Отклонение до края включает бег (Ctrl).
final class JoystickView: ControlView {
    private let knob = UIView()
    private var pressed = Set<Int>()

    override init(model: ControlButton) {
        super.init(model: model)
        knob.frame = CGRect(x: 0, y: 0, width: model.size * 0.42, height: model.size * 0.42)
        knob.layer.cornerRadius = knob.bounds.width / 2
        knob.backgroundColor = UIColor(white: 0.85, alpha: 0.8)
        knob.isUserInteractionEnabled = false
        addSubview(knob)
        knob.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func began(_ point: CGPoint) { moved(point) }

    override func moved(_ point: CGPoint) {
        let radius = bounds.width / 2
        var dx = point.x - bounds.midX, dy = point.y - bounds.midY
        let length = hypot(dx, dy)
        if length > radius { dx *= radius / length; dy *= radius / length }
        knob.center = CGPoint(x: bounds.midX + dx, y: bounds.midY + dy)

        let threshold = radius * 0.3
        let codes = model.codes // W, A, S, D
        var next = Set<Int>()
        if dy < -threshold { next.insert(codes[0]) }
        if dx < -threshold { next.insert(codes[1]) }
        if dy > threshold { next.insert(codes[2]) }
        if dx > threshold { next.insert(codes[3]) }
        if length > radius * 0.95 && dy < -threshold { next.insert(Int(GLFW.leftControl)) }
        apply(next)
    }

    override func ended() { reset() }

    override func reset() {
        knob.center = CGPoint(x: bounds.midX, y: bounds.midY)
        apply([])
    }

    private func apply(_ next: Set<Int>) {
        pressed.subtracting(next).forEach { Input.binding($0, false) }
        next.subtracting(pressed).forEach { Input.binding($0, true) }
        pressed = next
    }
}
