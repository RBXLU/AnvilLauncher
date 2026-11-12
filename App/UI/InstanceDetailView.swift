import SwiftUI

struct InstanceDetailView: View {
    @EnvironmentObject private var store: InstanceStore
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var settings: AppSettings
    @State var instance: Instance
    @State private var files: [String] = []
    @State private var browsing = false

    private var loaderInstalled: Bool { GameLauncher.resolveVersionID(instance) != nil }

    var body: some View {
        Form {
            Section {
                Button {
                    state.play(instance, accounts: accounts, store: store)
                } label: {
                    Label("Играть", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(instance.loader != .vanilla && !loaderInstalled)
                if instance.loader != .vanilla && !loaderInstalled {
                    Button("Установить \(instance.loader.title) \(instance.loaderVersion ?? "")") {
                        state.installLoader(for: instance, store: store)
                    }
                }
            }

            Section("Сборка") {
                TextField("Название", text: $instance.name)
                LabeledContent("Версия игры", value: instance.minecraftVersion)
                LabeledContent("Загрузчик", value: [instance.loader.title, instance.loaderVersion].compactMap { $0 }.joined(separator: " "))
            }

            Section("Производительность") {
                Toggle("Своя память", isOn: Binding(
                    get: { instance.memoryMB != nil },
                    set: { instance.memoryMB = $0 ? settings.memoryMB : nil }))
                if let memory = instance.memoryMB {
                    MemorySlider(value: Binding(get: { memory }, set: { instance.memoryMB = $0 }))
                }
                Picker("Рендерер", selection: Binding(get: { instance.renderer ?? settings.renderer }, set: { instance.renderer = $0 })) {
                    ForEach(Renderer.allCases) { Text($0.title).tag($0) }
                }
                TextField("Аргументы JVM", text: $instance.jvmArgs, prompt: Text("-XX:+UseG1GC"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.footnote.monospaced())
            }

            Section {
                ForEach(files, id: \.self) { file in
                    Toggle(isOn: Binding(get: { !file.hasSuffix(".disabled") }, set: { toggle(file, enabled: $0) })) {
                        Text(file.replacingOccurrences(of: ".disabled", with: "")).font(.footnote).lineLimit(2)
                    }
                }
                .onDelete { offsets in
                    offsets.forEach { try? FileManager.default.removeItem(at: instance.modsDirectory.appending(path: files[$0])) }
                    reload()
                }
                Button("Найти на Modrinth", systemImage: "plus") { browsing = true }
            } header: {
                Text("Моды (\(files.count))")
            } footer: {
                Text("Файлы сборки доступны в приложении «Файлы»: На iPhone → Anvil → instances.")
            }
        }
        .navigationTitle(instance.name)
        .onAppear(perform: reload)
        .onChange(of: instance) { store.update($0) }
        .sheet(isPresented: $browsing, onDismiss: reload) {
            NavigationStack { ModBrowserView(instance: instance) }
        }
    }

    private func reload() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: instance.modsDirectory.path)) ?? []
        files = names.filter { $0.hasSuffix(".jar") || $0.hasSuffix(".jar.disabled") }.sorted()
    }

    private func toggle(_ file: String, enabled: Bool) {
        let from = instance.modsDirectory.appending(path: file)
        let name = enabled ? file.replacingOccurrences(of: ".disabled", with: "") : file + ".disabled"
        try? FileManager.default.moveItem(at: from, to: instance.modsDirectory.appending(path: name))
        reload()
    }
}

struct MemorySlider: View {
    @Binding var value: Int
    private let maximum = max(2048, AppSettings.physicalMemoryMB * 3 / 4)

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Память")
                Spacer()
                Text("\(value) МБ").monospacedDigit().foregroundStyle(value > AppSettings.physicalMemoryMB / 2 ? .orange : .secondary)
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = Int($0) / 128 * 128 }), in: 512...Double(maximum), step: 128)
            Text("Всего в устройстве \(AppSettings.physicalMemoryMB) МБ. Больше половины — риск, что iOS закроет игру.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
