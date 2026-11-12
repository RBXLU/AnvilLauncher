import Foundation
import ZIPFoundation

enum Modrinth {
    static let api = "https://api.modrinth.com/v2"

    enum ProjectType: String, CaseIterable, Identifiable {
        case mod, resourcepack, shader, modpack
        var id: String { rawValue }
        var title: String {
            switch self {
            case .mod: return "Моды"
            case .resourcepack: return "Ресурспаки"
            case .shader: return "Шейдеры"
            case .modpack: return "Модпаки"
            }
        }
        var folder: String {
            switch self {
            case .mod, .modpack: return "mods"
            case .resourcepack: return "resourcepacks"
            case .shader: return "shaderpacks"
            }
        }
    }

    struct Hit: Decodable, Identifiable, Hashable {
        let projectId: String
        let title: String
        let description: String
        let author: String
        let downloads: Int
        let iconUrl: String?
        var id: String { projectId }
        enum CodingKeys: String, CodingKey {
            case projectId = "project_id", title, description, author, downloads, iconUrl = "icon_url"
        }
    }

    struct Version: Decodable, Identifiable {
        struct File: Decodable { let url: URL; let filename: String; let primary: Bool; let size: Int; let hashes: [String: String] }
        struct Dependency: Decodable {
            let projectId: String?
            let versionId: String?
            let dependencyType: String
            enum CodingKeys: String, CodingKey { case projectId = "project_id", versionId = "version_id", dependencyType = "dependency_type" }
        }
        let id: String
        let name: String
        let versionNumber: String
        let gameVersions: [String]
        let loaders: [String]
        let files: [File]
        let dependencies: [Dependency]
        enum CodingKeys: String, CodingKey {
            case id, name, versionNumber = "version_number", gameVersions = "game_versions", loaders, files, dependencies
        }
        var primaryFile: File? { files.first(where: \.primary) ?? files.first }
    }

    static func search(_ query: String, type: ProjectType, instance: Instance?, offset: Int = 0) async throws -> [Hit] {
        var facets = [["project_type:\(type.rawValue)"]]
        if let instance, type != .modpack {
            facets.append(["versions:\(instance.minecraftVersion)"])
            if type == .mod, let loader = instance.loader.modrinthName { facets.append(["categories:\(loader)"]) }
        }
        var components = URLComponents(string: "\(api)/search")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "index", value: query.isEmpty ? "downloads" : "relevance"),
            URLQueryItem(name: "facets", value: String(decoding: try JSONEncoder().encode(facets), as: UTF8.self)),
        ]
        struct Response: Decodable { let hits: [Hit] }
        return try await HTTP.json(Response.self, from: components.url!).hits
    }

    static func versions(project: String, instance: Instance?, type: ProjectType) async throws -> [Version] {
        var components = URLComponents(string: "\(api)/project/\(project)/version")!
        if let instance, type != .modpack {
            var items = [URLQueryItem(name: "game_versions", value: #"["\#(instance.minecraftVersion)"]"#)]
            if type == .mod, let loader = instance.loader.modrinthName {
                items.append(URLQueryItem(name: "loaders", value: #"["\#(loader)"]"#))
            }
            components.queryItems = items
        }
        return try await HTTP.json([Version].self, from: components.url!)
    }

    /// Ставит версию проекта в сборку вместе с обязательными зависимостями.
    static func install(_ version: Version, type: ProjectType, into instance: Instance, progress: TaskProgress) async throws {
        var queue = [version]
        var tasks: [DownloadTask] = []
        var visited = Set<String>()
        while let current = queue.popLast() {
            guard visited.insert(current.id).inserted, let file = current.primaryFile else { continue }
            tasks.append(DownloadTask(url: file.url, destination: instance.folder(type.folder).appending(path: file.filename),
                                      sha1: file.hashes["sha1"], size: file.size))
            guard type == .mod else { continue }
            for dep in current.dependencies where dep.dependencyType == "required" {
                if let versionId = dep.versionId {
                    queue.append(try await HTTP.json(Version.self, from: URL(string: "\(api)/version/\(versionId)")!))
                } else if let projectId = dep.projectId,
                          let latest = try await versions(project: projectId, instance: instance, type: .mod).first {
                    queue.append(latest)
                }
            }
        }
        try await Downloader.run(tasks, title: version.name, progress: progress)
    }

    // MARK: - Модпаки (.mrpack)

    struct PackIndex: Decodable {
        struct File: Decodable {
            struct Env: Decodable { let client: String? }
            let path: String
            let hashes: [String: String]
            let downloads: [URL]
            let fileSize: Int
            let env: Env?
        }
        let name: String
        let files: [File]
        let dependencies: [String: String]
    }

    /// Разворачивает .mrpack в новую сборку. Возвращает сборку и способ поставить загрузчик.
    static func importPack(_ archive: URL, progress: TaskProgress) async throws -> (Instance, Loader, String?) {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appending(path: UUID().uuidString)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        try fm.unzipItem(at: archive, to: temp)
        defer { try? fm.removeItem(at: temp) }
        let index = try JSONDecoder().decode(PackIndex.self, from: Data(contentsOf: temp.appending(path: "modrinth.index.json")))
        guard let mc = index.dependencies["minecraft"] else { throw LauncherError("В модпаке не указана версия игры") }

        let loaders: [(String, Loader)] = [("fabric-loader", .fabric), ("quilt-loader", .quilt), ("forge", .forge), ("neoforge", .neoforge)]
        let (loader, loaderVersion) = loaders.first { index.dependencies[$0.0] != nil }
            .map { ($0.1, index.dependencies[$0.0]) } ?? (.vanilla, nil)

        let instance = Instance(name: index.name, minecraftVersion: mc, loader: loader, versionID: mc)
        try fm.createDirectory(at: instance.directory, withIntermediateDirectories: true)
        let tasks = index.files.filter { $0.env?.client != "unsupported" }.compactMap { file -> DownloadTask? in
            // Защита от путей вида ../../ внутри архива.
            guard let url = file.downloads.first, !file.path.contains("..") else { return nil }
            return DownloadTask(url: url, destination: instance.directory.appending(path: file.path),
                                sha1: file.hashes["sha1"], size: file.fileSize)
        }
        try await Downloader.run(tasks, title: index.name, progress: progress)

        for overrides in ["overrides", "client-overrides"] {
            let src = temp.appending(path: overrides)
            guard let items = fm.enumerator(at: src, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for case let item as URL in items.allObjects where (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false {
                let relative = item.path.replacingOccurrences(of: src.path + "/", with: "")
                let dest = instance.directory.appending(path: relative)
                try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: dest)
                try fm.copyItem(at: item, to: dest)
            }
        }
        return (instance, loader, loader == .forge ? "\(mc)-\(loaderVersion ?? "")" : loaderVersion)
    }
}
