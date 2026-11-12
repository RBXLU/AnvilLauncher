import Foundation

enum LoaderInstaller {
    /// Версии загрузчика, подходящие под версию игры. Первая — рекомендуемая.
    static func versions(of loader: Loader, for mc: String) async throws -> [String] {
        switch loader {
        case .vanilla:
            return []
        case .fabric, .quilt:
            struct Entry: Decodable { struct L: Decodable { let version: String }; let loader: L }
            let base = loader == .fabric ? "https://meta.fabricmc.net/v2" : "https://meta.quiltmc.org/v3"
            return try await HTTP.json([Entry].self, from: URL(string: "\(base)/versions/loader/\(mc)")!).map(\.loader.version)
        case .forge:
            let xml = try await HTTP.data(URL(string: "https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml")!)
            return mavenVersions(xml).filter { $0.hasPrefix("\(mc)-") }.reversed()
        case .neoforge:
            let xml = try await HTTP.data(URL(string: "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml")!)
            let prefix = neoForgePrefix(mc)
            return mavenVersions(xml).filter { $0.hasPrefix(prefix) }.reversed()
        }
    }

    /// 1.21.1 -> "21.1.", 1.21 -> "21.0.", 26.1 -> "26.1."
    static func neoForgePrefix(_ mc: String) -> String {
        var parts = mc.split(separator: ".").map(String.init)
        if parts.first == "1" { parts.removeFirst() }
        if parts.count == 1 { parts.append("0") }
        return parts.prefix(2).joined(separator: ".") + "."
    }

    private static func mavenVersions(_ xml: Data) -> [String] {
        let text = String(decoding: xml, as: UTF8.self)
        return text.components(separatedBy: "<version>").dropFirst().compactMap { $0.components(separatedBy: "</version>").first }
    }

    enum Result {
        case ready(versionID: String)
        /// Forge и NeoForge ставятся своим установщиком внутри JVM, после чего приложение перезапускается.
        case needsInstaller(jar: URL, versionID: String)
    }

    static func install(_ loader: Loader, version: String, mc: String) async throws -> Result {
        try await VersionManager.ensureVanillaJSON(mc)
        switch loader {
        case .vanilla:
            return .ready(versionID: mc)
        case .fabric, .quilt:
            let base = loader == .fabric ? "https://meta.fabricmc.net/v2" : "https://meta.quiltmc.org/v3"
            let data = try await HTTP.data(URL(string: "\(base)/versions/loader/\(mc)/\(version)/profile/json")!)
            let info = try HTTP.decoder.decode(VersionInfo.self, from: data)
            let file = Paths.versionJSON(info.id)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
            return .ready(versionID: info.id)
        case .forge:
            let url = URL(string: "https://maven.minecraftforge.net/net/minecraftforge/forge/\(version)/forge-\(version)-installer.jar")!
            let forgeVersion = version.replacingOccurrences(of: "\(mc)-", with: "")
            return .needsInstaller(jar: try await downloadInstaller(url), versionID: "\(mc)-forge-\(forgeVersion)")
        case .neoforge:
            let url = URL(string: "https://maven.neoforged.net/releases/net/neoforged/neoforge/\(version)/neoforge-\(version)-installer.jar")!
            return .needsInstaller(jar: try await downloadInstaller(url), versionID: "neoforge-\(version)")
        }
    }

    private static func downloadInstaller(_ url: URL) async throws -> URL {
        let dest = Paths.root.appending(path: "installers/\(url.lastPathComponent)")
        try await Downloader.fetch(DownloadTask(url: url, destination: dest))
        return dest
    }
}
