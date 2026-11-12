import GameController
import QuartzCore
import UIKit

/// Поверхность, в которую рисует ANGLE (Metal). Размер в пикселях учитывает масштаб разрешения.
final class SurfaceView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    var pixelScale: CGFloat { window?.screen.nativeScale ?? UIScreen.main.nativeScale }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = pixelScale * AppSettings.shared.resolutionScale
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        guard let metal = layer as? CAMetalLayer, size.width > 0 else { return }
        metal.contentsScale = scale
        metal.drawableSize = size
        anvil_set_surface(Unmanaged.passUnretained(metal).toOpaque(), Int32(size.width), Int32(size.height))
    }

    /// Перевод точки экрана в координаты окна игры.
    func gamePoint(_ point: CGPoint) -> CGPoint {
        let scale = pixelScale * AppSettings.shared.resolutionScale
        return CGPoint(x: point.x * scale, y: point.y * scale)
    }
}

/// Мост из C-колбэка захвата курсора в UIKit.
private func grabChanged(_ grabbed: Bool) {
    DispatchQueue.main.async { NotificationCenter.default.post(name: .anvilGrabChanged, object: nil) }
}

extension Notification.Name {
    static let anvilGrabChanged = Notification.Name("anvilGrabChanged")
}

final class GameViewController: UIViewController {
    private let args: [String]
    private let isInstaller: Bool
    private let surface = SurfaceView()
    private let overlay = ControlsOverlay()
    private let keyboardInput = SoftKeyboardInput()
    private let menuButton = UIButton(type: .system)
    private let logView = UITextView()
    private var started = false
    private var settings: AppSettings { .shared }

    // Касание камеры/курсора
    private var lookTouch: UITouch?
    private var lookStart = Date()
    private var lookMoved = false
    private var holdTimer: Timer?
    private var holdingAttack = false

    // Геймпад
    private var displayLink: CADisplayLink?
    private var stickKeys = Set<Int32>()
    private var lastFrame = CACurrentMediaTime()

    init(args: [String], isInstaller: Bool = false) {
        self.args = args
        self.isInstaller = isInstaller
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var prefersPointerLocked: Bool { anvil_is_grabbed() }
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = true
        surface.isMultipleTouchEnabled = true
        overlay.onKeyboard = { [weak self] in self?.toggleKeyboard() }
        for v in [surface, overlay] {
            v.frame = view.bounds
            v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(v)
        }
        view.addSubview(keyboardInput)
        if args.isEmpty { addDemoBackdrop() }
        setupMenu()
        setupLog()

        anvil_set_grab_callback(grabChanged)
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(grabDidChange), name: .anvilGrabChanged, object: nil)
        for name in [Notification.Name.GCMouseDidConnect, .GCControllerDidConnect, .GCKeyboardDidConnect,
                     .GCMouseDidDisconnect, .GCControllerDidDisconnect, .GCKeyboardDidDisconnect] {
            center.addObserver(self, selector: #selector(devicesChanged), name: name, object: nil)
        }
        center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.overlay.releaseAll()
        }
        devicesChanged()

        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)

        if isInstaller {
            // Установщик Forge/NeoForge работает без окна: показываем его лог, по завершении приложение закроется.
            overlay.isHidden = true
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refreshLog(show: true) }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        // Играть удобнее горизонтально: просим сцену повернуться.
        view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        guard !started, !args.isEmpty else { return }
        started = true
        surface.layoutIfNeeded()
        do {
            try GameLauncher.start(args)
        } catch {
            logView.isHidden = false
            logView.text = error.localizedDescription
        }
    }

    /// Для демо-режима без JVM: небо и трава вместо кадра игры.
    private func addDemoBackdrop() {
        let backdrop = GradientView(frame: view.bounds)
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backdrop.isUserInteractionEnabled = false
        let gradient = backdrop.layer as! CAGradientLayer
        gradient.colors = [UIColor(red: 0.45, green: 0.68, blue: 1, alpha: 1).cgColor,
                           UIColor(red: 0.72, green: 0.85, blue: 1, alpha: 1).cgColor,
                           UIColor(red: 0.36, green: 0.62, blue: 0.25, alpha: 1).cgColor,
                           UIColor(red: 0.42, green: 0.3, blue: 0.2, alpha: 1).cgColor]
        gradient.locations = [0, 0.55, 0.56, 1]
        view.insertSubview(backdrop, aboveSubview: surface)
    }

    // MARK: - Меню и лог

    private func setupMenu() {
        menuButton.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        menuButton.tintColor = .white
        menuButton.alpha = 0.7
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(menuButton)
        NSLayoutConstraint.activate([
            menuButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            menuButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            menuButton.widthAnchor.constraint(equalToConstant: 36),
            menuButton.heightAnchor.constraint(equalToConstant: 36),
        ])
        rebuildMenu()
    }

    private func rebuildMenu() {
        menuButton.menu = UIMenu(children: [
            UIAction(title: "Клавиатура", image: UIImage(systemName: "keyboard")) { [weak self] _ in self?.toggleKeyboard() },
            UIAction(title: overlay.isEditing ? "Готово" : "Редактировать кнопки", image: UIImage(systemName: "slider.horizontal.3")) { [weak self] _ in
                guard let self else { return }
                overlay.isEditing.toggle()
                rebuildMenu()
            },
            UIAction(title: "Добавить кнопку", image: UIImage(systemName: "plus.circle"), attributes: overlay.isEditing ? [] : .hidden) { [weak self] _ in
                self?.overlay.addButton()
            },
            UIAction(title: overlay.isHidden ? "Показать кнопки" : "Скрыть кнопки", image: UIImage(systemName: "eye")) { [weak self] _ in
                guard let self else { return }
                overlay.isHidden.toggle()
                rebuildMenu()
            },
            UIAction(title: "Лог", image: UIImage(systemName: "doc.text")) { [weak self] _ in self?.toggleLog() },
        ])
    }

    private func setupLog() {
        logView.isHidden = true
        logView.isEditable = false
        logView.backgroundColor = UIColor(white: 0, alpha: 0.75)
        logView.textColor = .green
        logView.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        logView.frame = view.bounds.insetBy(dx: 40, dy: 40)
        logView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(logView)
    }

    private func toggleLog() { refreshLog(show: logView.isHidden) }

    private func refreshLog(show: Bool) {
        logView.isHidden = !show
        guard show, let data = try? Data(contentsOf: GameLauncher.logFile) else { return }
        logView.text = String(decoding: data.suffix(64_000), as: UTF8.self)
        logView.scrollRangeToVisible(NSRange(location: logView.text.count, length: 0))
    }

    private func toggleKeyboard() {
        if keyboardInput.isFirstResponder { becomeFirstResponder() } else { keyboardInput.becomeFirstResponder() }
    }

    // MARK: - Захват курсора и устройства

    @objc private func grabDidChange() {
        setNeedsUpdateOfPrefersPointerLocked()
        overlay.releaseAll()
    }

    @objc private func devicesChanged() {
        GCMouse.mice().forEach(configure)
        GCController.controllers().forEach(configure)
        // Одна клавиатура камеру не заменит, поэтому кнопки прячем только при мыши или геймпаде.
        let external = GCMouse.current != nil || GCController.current?.extendedGamepad != nil
        // В демо (без JVM) кнопки показываем всегда: в симуляторе трекпад Mac виден как мышь.
        overlay.isHidden = external && settings.hideControlsWithInputDevice && !args.isEmpty
        rebuildMenu()
    }

    private func configure(_ mouse: GCMouse) {
        guard let input = mouse.mouseInput else { return }
        input.mouseMovedHandler = { [weak self] _, dx, dy in
            let s = (self?.settings.sensitivity ?? 1)
            anvil_send_cursor_delta(Double(dx) * s, Double(-dy) * s)
        }
        input.leftButton.pressedChangedHandler = { _, _, pressed in Input.mouse(GLFW.mouseLeft, pressed) }
        input.rightButton?.pressedChangedHandler = { _, _, pressed in Input.mouse(GLFW.mouseRight, pressed) }
        input.middleButton?.pressedChangedHandler = { _, _, pressed in Input.mouse(GLFW.mouseMiddle, pressed) }
        input.scroll.valueChangedHandler = { _, x, y in
            if x != 0 || y != 0 { anvil_send_scroll(Double(x), Double(y)) }
        }
    }

    private func configure(_ controller: GCController) {
        guard let pad = controller.extendedGamepad else { return }
        // Кнопки, которые в мире и в меню значат разное.
        func bind(_ button: GCControllerButtonInput?, game: Int, menu: Int? = nil) {
            button?.pressedChangedHandler = { _, _, pressed in
                Input.binding(anvil_is_grabbed() ? game : (menu ?? game), pressed)
            }
        }
        bind(pad.buttonA, game: Int(GLFW.space), menu: GLFW.mouseLeftCode)
        bind(pad.buttonB, game: Int(GLFW.leftShift), menu: Int(GLFW.escape))
        bind(pad.buttonX, game: Int(GLFW.key("Q")), menu: GLFW.mouseRightCode)
        bind(pad.buttonY, game: Int(GLFW.key("E")))
        bind(pad.rightTrigger, game: GLFW.mouseLeftCode)
        bind(pad.leftTrigger, game: GLFW.mouseRightCode)
        bind(pad.rightShoulder, game: GLFW.scrollDownCode)
        bind(pad.leftShoulder, game: GLFW.scrollUpCode)
        bind(pad.buttonMenu, game: Int(GLFW.escape))
        bind(pad.buttonOptions, game: Int(GLFW.tab))
        bind(pad.leftThumbstickButton, game: Int(GLFW.leftControl))
        bind(pad.rightThumbstickButton, game: GLFW.mouseMiddleCode)
        bind(pad.dpad.up, game: Int(GLFW.f5))
        bind(pad.dpad.down, game: Int(GLFW.key("T")))
        bind(pad.dpad.left, game: GLFW.scrollUpCode)
        bind(pad.dpad.right, game: GLFW.scrollDownCode)
    }

    /// Стики опрашиваются каждый кадр: так камера крутится плавно и при неподвижном стике.
    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastFrame, 0.1)
        lastFrame = now
        guard let pad = GCController.current?.extendedGamepad else { return }
        let dead = Float(settings.gamepadDeadzone)

        let right = pad.rightThumbstick
        let speed = 900.0 * settings.sensitivity * dt
        if abs(right.xAxis.value) > dead || abs(right.yAxis.value) > dead {
            anvil_send_cursor_delta(Double(right.xAxis.value) * speed, Double(-right.yAxis.value) * speed)
        }

        let left = pad.leftThumbstick
        if anvil_is_grabbed() {
            var keys = Set<Int32>()
            if left.yAxis.value > dead { keys.insert(GLFW.key("W")) }
            if left.yAxis.value < -dead { keys.insert(GLFW.key("S")) }
            if left.xAxis.value < -dead { keys.insert(GLFW.key("A")) }
            if left.xAxis.value > dead { keys.insert(GLFW.key("D")) }
            applyStick(keys)
        } else {
            applyStick([])
            if abs(left.xAxis.value) > dead || abs(left.yAxis.value) > dead {
                anvil_send_cursor_delta(Double(left.xAxis.value) * speed, Double(-left.yAxis.value) * speed)
            }
        }
    }

    private func applyStick(_ keys: Set<Int32>) {
        stickKeys.subtracting(keys).forEach { Input.key($0, false) }
        keys.subtracting(stickKeys).forEach { Input.key($0, true) }
        stickKeys = keys
    }

    // MARK: - Касания: камера в мире, курсор в меню

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard lookTouch == nil, let touch = touches.first else { return }
        lookTouch = touch
        lookStart = Date()
        lookMoved = false
        if anvil_is_grabbed() {
            // Долгое удержание — ломать блок, короткий тап — использовать предмет.
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                guard let self, !self.lookMoved else { return }
                self.holdingAttack = true
                Input.mouse(GLFW.mouseLeft, true)
            }
        } else {
            let p = surface.gamePoint(touch.location(in: surface))
            anvil_send_cursor_pos(Double(p.x), Double(p.y))
            Input.mouse(GLFW.mouseLeft, true)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = lookTouch, touches.contains(touch) else { return }
        let now = touch.location(in: surface), before = touch.previousLocation(in: surface)
        if hypot(now.x - before.x, now.y - before.y) > 1 { lookMoved = true }
        if anvil_is_grabbed() {
            let s = settings.sensitivity * 2
            anvil_send_cursor_delta(Double(now.x - before.x) * s, Double(now.y - before.y) * s)
        } else {
            let p = surface.gamePoint(now)
            anvil_send_cursor_pos(Double(p.x), Double(p.y))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = lookTouch, touches.contains(touch) else { return }
        lookTouch = nil
        holdTimer?.invalidate()
        if holdingAttack {
            holdingAttack = false
            Input.mouse(GLFW.mouseLeft, false)
        } else if anvil_is_grabbed() {
            if !lookMoved && Date().timeIntervalSince(lookStart) < 0.3 {
                Input.mouse(GLFW.mouseRight, true)
                Input.mouse(GLFW.mouseRight, false)
            }
        } else {
            Input.mouse(GLFW.mouseLeft, false)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: - Аппаратная клавиатура

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !handle(presses, pressed: true) { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !handle(presses, pressed: false) { super.pressesEnded(presses, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if !handle(presses, pressed: false) { super.pressesCancelled(presses, with: event) }
    }

    private func handle(_ presses: Set<UIPress>, pressed: Bool) -> Bool {
        var handled = false
        for press in presses {
            guard let key = press.key, let code = GLFW.from(hid: key.keyCode) else { continue }
            let mods = GLFW.mods(key.modifierFlags)
            Input.key(code, pressed, mods: mods)
            if pressed, key.modifierFlags.isDisjoint(with: [.control, .command]) {
                for scalar in key.characters.unicodeScalars where scalar.value >= 32 && scalar.value != 127 {
                    anvil_send_char(scalar.value, mods)
                }
            }
            handled = true
        }
        return handled
    }
}

private final class GradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
}

/// Невидимое поле для экранной клавиатуры: текст уходит в игру как символы GLFW.
final class SoftKeyboardInput: UIView, UIKeyInput {
    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { true }
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no

    func insertText(_ text: String) { Input.text(text) }

    func deleteBackward() {
        Input.key(GLFW.backspace, true)
        Input.key(GLFW.backspace, false)
    }
}
