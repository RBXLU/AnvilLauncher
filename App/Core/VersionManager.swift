import Foundation

enum VersionManager {
    static let manifestURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!

    static func manifest() async throws -> [VersionManifest.Entry] {
        try await HTTP.json(VersionManifest.self, from: manifestURL).versions
    }

    /// Скачивает json ванильной версии, если его ещё нет.
    static func ensureVanillaJSON(_ id: String) async throws {
        let file = Paths.versionJSON(id)
        if FileManager.default.fileExists(atPath: file.path) { return }
        guard let entry = try await manifest().first(where: { $0.id == id }) else {
            throw LauncherError("Версия \(id) не найдена в манифесте Mojang")
        }
        try await Downloader.fetch(DownloadTask(url: entry.url, destination: file))
    }

    /// Читает json версии и рекурсивно склеивает с родителем (inheritsFrom).
    static func resolve(_ id: String) async throws -> VersionInfo {
        let file = Paths.versionJSON(id)
        if !FileManager.default.fileExists(atPath: file.path) { try await ensureVanillaJSON(id) }
        let info = try HTTP.decoder.decode(VersionInfo.self, from: Data(contentsOf: file))
        guard let parent = info.inheritsFrom else { return info }
        return info.merged(onto: try await resolve(parent))
    }

    /// Ванильный jar, к которому относится версия (у модлоадеров — jar родителя).
    static func clientJarID(_ id: String) throws -> String {
        let data = try Data(contentsOf: Paths.versionJSON(id))
        let info = try HTTP.decoder.decode(VersionInfo.self, from: data)
        if info.downloads?["client"] != nil || info.inheritsFrom == nil { return id }
        return try clientJarID(info.inheritsFrom!)
    }

    /// Библиотеки, которые реально идут в classpath на iOS: без нативных и без LWJGL от Mojang.
    static func libraries(of info: VersionInfo) -> [Library] {
        var seen = Set<String>()
        return (info.libraries ?? []).filter { lib in
            guard lib.rules.allowed, !lib.isNative, !lib.group.hasPrefix("org.lwjgl") else { return false }
            return seen.insert(lib.key).inserted
        }
    }

    static func usesLegacyLWJGL(_ info: VersionInfo) -> Bool {
        (info.libraries ?? []).contains { $0.group == "org.lwjgl.lwjgl" }
    }

    static func install(_ id: String, progress: TaskProgress) async throws -> VersionInfo {
        let info = try await resolve(id)
        let jarID = try clientJarID(id)
        var tasks: [DownloadTask] = []
        if let client = try await resolve(jarID).downloads?["client"] {
            tasks.append(DownloadTask(url: URL(string: client.url)!, destination: Paths.versionJar(jarID), sha1: client.sha1, size: client.size))
        }
        for lib in libraries(of: info) {
            guard let d = lib.download, let path = d.path, let url = URL(string: d.url) else { continue }
            tasks.append(DownloadTask(url: url, destination: Paths.libraries.appending(path: path), sha1: d.sha1, size: d.size))
        }
        try await Downloader.run(tasks, title: "Библиотеки \(id)", progress: progress)
        try await installAssets(info, progress: progress)
        return info
    }

    static func installAssets(_ info: VersionInfo, progress: TaskProgress) async throws {
        guard let ref = info.assetIndex else { return }
        let indexFile = Paths.assets.appending(path: "indexes/\(ref.id).json")
        try await Downloader.run([DownloadTask(url: ref.url, destination: indexFile, sha1: ref.sha1)],
                                 title: "Индекс ассетов", progress: progress)
        let index = try HTTP.decoder.decode(AssetIndex.self, from: Data(contentsOf: indexFile))
        let tasks = index.objects.values.map { obj in
            let path = "\(obj.hash.prefix(2))/\(obj.hash)"
            return DownloadTask(url: URL(string: "https://resources.download.minecraft.net/\(path)")!,
                                destination: Paths.assets.appending(path: "objects/\(path)"),
                                sha1: obj.hash, size: obj.size)
        }
        try await Downloader.run(tasks, title: "Ассеты \(ref.id)", progress: progress)

        // Старые версии (до 1.7.10) читают ассеты по человеческим путям.
        guard index.virtual == true || index.mapToResources == true else { return }
        let target = index.mapToResources == true
            ? Paths.root.appending(path: "resources")
            : Paths.assets.appending(path: "virtual/\(ref.id)")
        let fm = FileManager.default
        for (name, obj) in index.objects {
            let dest = target.appending(path: name)
            guard !fm.fileExists(atPath: dest.path) else { continue }
            try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: Paths.assets.appending(path: "objects/\(obj.hash.prefix(2))/\(obj.hash)"), to: dest)
        }
    }
}
