import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var jit = JIT.status
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("JIT") {
                    LabeledContent("Статус", value: jit.debugged ? "включён" : "выключен")
                    if jit.debugged && JIT.needsTXMWorkaround {
                        LabeledContent("Режим", value: "iOS 26 + TXM: нужен скрипт StikDebug")
                    }
                    Button("Обновить") { jit = JIT.status }
                    Text("Без JIT Java на iOS не запускается. Включите его через StikDebug, SideStore или Xcode перед нажатием «Играть» — лаунчер дождётся сам.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Java") {
                    MemorySlider(value: $settings.memoryMB)
                    TextField("Общие аргументы JVM", text: $settings.jvmArgs, prompt: Text("-XX:+UseG1GC"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                }

                Section("Графика") {
                    Picker("Рендерер", selection: $settings.renderer) {
                        ForEach(Renderer.allCases) { Text($0.title).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text("Разрешение: \(Int(settings.resolutionScale * 100))%")
                        Slider(value: $settings.resolutionScale, in: 0.25...1, step: 0.05)
                    }
                }

                Section("Управление") {
                    VStack(alignment: .leading) {
                        Text("Чувствительность: \(settings.sensitivity, specifier: "%.2f")")
                        Slider(value: $settings.sensitivity, in: 0.2...3)
                    }
                    VStack(alignment: .leading) {
                        Text("Прозрачность кнопок: \(Int(settings.controlsOpacity * 100))%")
                        Slider(value: $settings.controlsOpacity, in: 0.1...1)
                    }
                    VStack(alignment: .leading) {
                        Text("Мёртвая зона стиков: \(Int(settings.gamepadDeadzone * 100))%")
                        Slider(value: $settings.gamepadDeadzone, in: 0.05...0.5)
                    }
                    Toggle("Прятать кнопки при подключённой мыши, клавиатуре или геймпаде", isOn: $settings.hideControlsWithInputDevice)
                    Button("Сбросить раскладку кнопок", role: .destructive) { confirmReset = true }
                    Text("Кнопки редактируются прямо в игре: меню ⋯ → «Редактировать кнопки». Перетаскивайте их, а долгим нажатием меняйте назначение и размер.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("О приложении") {
                    LabeledContent("Устройство", value: "\(AppSettings.physicalMemoryMB) МБ ОЗУ")
                    LabeledContent("Данные", value: "Файлы → На iPhone → Anvil")
                }
            }
            .navigationTitle("Настройки")
            .onAppear { jit = JIT.status }
            .confirmationDialog("Вернуть стандартную раскладку?", isPresented: $confirmReset) {
                Button("Сбросить", role: .destructive) { try? FileManager.default.removeItem(at: ControlLayout.file) }
            }
        }
    }
}
