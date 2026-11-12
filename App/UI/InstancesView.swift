import SwiftUI
import UniformTypeIdentifiers

struct InstancesView: View {
    @EnvironmentObject private var store: InstanceStore
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var accounts: AccountStore
    @State private var creating = false
    @State private var importing = false
    @State private var path: [UUID] = []

    private var sorted: [Instance] {
        store.instances.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if store.instances.isEmpty {
                    ContentUnavailableHint(title: "Сборок пока нет",
                                           text: "Создайте сборку: выберите версию игры и, если нужно, загрузчик модов.")
                }
                ForEach(sorted) { instance in
                    NavigationLink(value: instance.id) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(instance.name).font(.headline)
                                Text("\(instance.minecraftVersion) · \(instance.loader.title)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                state.play(instance, accounts: accounts, store: store)
                            } label: {
                                Image(systemName: "play.fill").padding(10)
                            }
                            .buttonStyle(.borderedProminent)
                            .clipShape(Circle())
                        }
                    }
                }
                .onDelete { offsets in offsets.map { sorted[$0] }.forEach(store.remove) }
            }
            .navigationTitle("Сборки")
            .navigationDestination(for: UUID.self) { id in
                if let instance = store.instances.first(where: { $0.id == id }) { InstanceDetailView(instance: instance) }
            }
            .toolbar {
                Menu {
                    Button("Новая сборка", systemImage: "plus") { creating = true }
                    Button("Импорт .mrpack", systemImage: "square.and.arrow.down") { importing = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $creating) { NewInstanceView() }
            .onAppear {
                if Demo.screen == "detail", let first = sorted.first { path = [first.id] }
                if Demo.screen == "new" { creating = true }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "mrpack") ?? .zip, .zip]) { result in
                guard case .success(let url) = result else { return }
                importPack(url)
            }
        }
    }

    private func importPack(_ url: URL) {
        state.perform {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            var (instance, loader, version) = try await Modrinth.importPack(url, progress: state.progress)
            instance.loaderVersion = version
            store.add(instance)
            if loader != .vanilla { try await state.loaderStep(instance, store: store) }
        }
    }
}

struct ContentUnavailableHint: View {
    let title: String
    let text: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

struct NewInstanceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InstanceStore
    @EnvironmentObject private var state: AppState
    @State private var name = ""
    @State private var versions: [VersionManifest.Entry] = []
    @State private var showSnapshots = false
    @State private var version = ""
    @State private var loader = Loader.vanilla
    @State private var loaderVersions: [String] = []
    @State private var loaderVersion = ""
    @State private var loadingLoaders = false

    private var visible: [VersionManifest.Entry] {
        versions.filter { showSnapshots || $0.type == "release" }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $name, prompt: Text(version.isEmpty ? "Моя сборка" : "\(loader.title) \(version)"))
                Section("Версия игры") {
                    Toggle("Показывать снапшоты и старые версии", isOn: $showSnapshots)
                    if versions.isEmpty {
                        ProgressView()
                    } else {
                        Picker("Версия", selection: $version) {
                            ForEach(visible) { Text($0.id).tag($0.id) }
                        }
                    }
                }
                Section("Загрузчик модов") {
                    Picker("Загрузчик", selection: $loader) {
                        ForEach(Loader.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if loader != .vanilla {
                        if loadingLoaders {
                            ProgressView()
                        } else if loaderVersions.isEmpty {
                            Text("Для \(version) нет версий \(loader.title)").foregroundStyle(.secondary)
                        } else {
                            Picker("Версия загрузчика", selection: $loaderVersion) {
                                ForEach(loaderVersions, id: \.self) { Text($0).tag($0) }
                            }
                        }
                    }
                    if loader == .forge || loader == .neoforge {
                        Text("Установщик \(loader.title) запустится внутри приложения. После установки Anvil закроется — просто откройте его снова.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Новая сборка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать", action: create)
                        .disabled(version.isEmpty || (loader != .vanilla && loaderVersion.isEmpty))
                }
            }
            .task {
                versions = (try? await VersionManager.manifest()) ?? []
                version = versions.first { $0.type == "release" }?.id ?? ""
            }
            .task(id: "\(loader.rawValue)|\(version)") { await loadLoaderVersions() }
        }
    }

    private func loadLoaderVersions() async {
        loaderVersions = []
        loaderVersion = ""
        guard loader != .vanilla, !version.isEmpty else { return }
        loadingLoaders = true
        loaderVersions = (try? await LoaderInstaller.versions(of: loader, for: version)) ?? []
        loaderVersion = loaderVersions.first ?? ""
        loadingLoaders = false
    }

    private func create() {
        let instance = Instance(name: name.isEmpty ? "\(loader.title) \(version)" : name,
                                minecraftVersion: version, loader: loader,
                                loaderVersion: loader == .vanilla ? nil : loaderVersion, versionID: version)
        store.add(instance)
        if loader != .vanilla { state.installLoader(for: instance, store: store) }
        dismiss()
    }
}
