import SwiftUI

struct ModBrowserView: View {
    /// nil — общий каталог: сборку выбирают при установке.
    let instance: Instance?
    @EnvironmentObject private var store: InstanceStore
    @State private var query = ""
    @State private var type = Modrinth.ProjectType.mod
    @State private var hits: [Modrinth.Hit] = []
    @State private var loading = false
    @State private var selected: Modrinth.Hit?

    var body: some View {
        let list = List {
            Picker("Тип", selection: $type) {
                ForEach(Modrinth.ProjectType.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            ForEach(hits) { hit in
                Button { selected = hit } label: { HitRow(hit: hit) }
                    .buttonStyle(.plain)
                    .onAppear { if hit == hits.last { Task { await load(more: true) } } }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
        }
        .searchable(text: $query, prompt: "Поиск на Modrinth")
        .navigationTitle(instance.map { "Моды · \($0.name)" } ?? "Modrinth")
        .task(id: "\(type.rawValue)|\(query)") {
            try? await Task.sleep(nanoseconds: 350_000_000) // не дёргаем API на каждую букву
            await load(more: false)
        }
        .sheet(item: $selected) { hit in
            NavigationStack { ProjectVersionsView(hit: hit, type: type, fixedInstance: instance) }
        }

        if instance == nil { NavigationStack { list } } else { list }
    }

    private func load(more: Bool) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        let page = (try? await Modrinth.search(query, type: type, instance: instance, offset: more ? hits.count : 0)) ?? []
        hits = more ? hits + page : page
    }
}

private struct HitRow: View {
    let hit: Modrinth.Hit
    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: hit.iconUrl.flatMap(URL.init(string:))) { $0.resizable() } placeholder: { Color.gray.opacity(0.2) }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.title).font(.headline)
                Text(hit.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text("\(hit.author) · \(hit.downloads.formatted(.number.notation(.compactName))) загрузок")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

struct ProjectVersionsView: View {
    let hit: Modrinth.Hit
    let type: Modrinth.ProjectType
    let fixedInstance: Instance?
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: InstanceStore
    @EnvironmentObject private var state: AppState
    @State private var targetID: UUID?
    @State private var versions: [Modrinth.Version] = []
    @State private var loading = true

    private var target: Instance? { fixedInstance ?? store.instances.first { $0.id == targetID } }

    var body: some View {
        List {
            if fixedInstance == nil && type != .modpack {
                Picker("Сборка", selection: $targetID) {
                    Text("Не выбрана").tag(UUID?.none)
                    ForEach(store.instances) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
            if loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if versions.isEmpty {
                Text("Нет версий для этой сборки").foregroundStyle(.secondary)
            }
            ForEach(versions) { version in
                Button { install(version) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(version.name).font(.subheadline.weight(.semibold))
                        Text("\(version.loaders.joined(separator: ", ")) · \(version.gameVersions.suffix(3).joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(type != .modpack && target == nil)
            }
        }
        .navigationTitle(hit.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Закрыть") { dismiss() } }
        .task(id: targetID) {
            loading = true
            versions = (try? await Modrinth.versions(project: hit.projectId, instance: target, type: type)) ?? []
            loading = false
        }
    }

    private func install(_ version: Modrinth.Version) {
        let instance = target
        dismiss()
        state.perform {
            if type == .modpack {
                guard let file = version.primaryFile else { return }
                let local = Paths.root.appending(path: "installers/\(file.filename)")
                try await Downloader.fetch(DownloadTask(url: file.url, destination: local, sha1: file.hashes["sha1"]))
                var (pack, loader, loaderVersion) = try await Modrinth.importPack(local, progress: state.progress)
                pack.loaderVersion = loaderVersion
                store.add(pack)
                if loader != .vanilla { try await state.loaderStep(pack, store: store) }
            } else if let instance {
                try await Modrinth.install(version, type: type, into: instance, progress: state.progress)
            }
        }
    }
}
