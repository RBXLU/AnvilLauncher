import Foundation

struct VersionManifest: Decodable {
    struct Entry: Decodable, Identifiable, Hashable {
        let id: String
        let type: String
        let url: URL
        let releaseTime: Date
    }
    let versions: [Entry]
}

struct Download: Codable, Hashable {
    /// Строка, а не URL: Forge кладёт сюда "" для файлов, которые генерирует установщик.
    var url: String
    var sha1: String?
    var size: Int?
    var path: String?
}

struct Rule: Codable {
    struct OS: Codable { var name: String?; var arch: String? }
    var action: String
    var os: OS?
    var features: [String: Bool]?

    /// Правила оцениваются так, будто мы macOS на arm64: это ближайшая к iOS платформа Mojang.
    var matches: Bool {
        if let name = os?.name, name != "osx", name != "macos" { return false }
        if let arch = os?.arch, arch != "arm64", arch != "aarch64" { return false }
        if let features {
            let supported: Set<String> = ["has_custom_resolution"]
            return features.allSatisfy { supported.contains($0.key) == $0.value }
        }
        return true
    }
}

extension Optional where Wrapped == [Rule] {
    var allowed: Bool {
        guard let rules = self, !rules.isEmpty else { return true }
        return rules.reduce(false) { $1.matches ? $1.action == "allow" : $0 }
    }
}

enum Argument: Codable {
    case plain(String)
    case conditional(rules: [Rule], values: [String])

    private enum Keys: String, CodingKey { case rules, value }

    init(from decoder: Decoder) throws {
        if let string = try? decoder.singleValueContainer().decode(String.self) {
            self = .plain(string)
            return
        }
        let c = try decoder.container(keyedBy: Keys.self)
        let rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        if let single = try? c.decode(String.self, forKey: .value) {
            self = .conditional(rules: rules, values: [single])
        } else {
            self = .conditional(rules: rules, values: try c.decode([String].self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .plain(let s):
            var c = encoder.singleValueContainer()
            try c.encode(s)
        case .conditional(let rules, let values):
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(rules, forKey: .rules)
            try c.encode(values, forKey: .value)
        }
    }

    var resolved: [String] {
        switch self {
        case .plain(let s): return [s]
        case .conditional(let rules, let values): return Optional(rules).allowed ? values : []
        }
    }
}

struct Library: Codable {
    struct Downloads: Codable { var artifact: Download?; var classifiers: [String: Download]? }
    var name: String
    var url: String?
    var downloads: Downloads?
    var rules: [Rule]?
    var natives: [String: String]?
    var sha1: String?
    var size: Int?

    private var parts: [String] { name.split(separator: "@")[0].split(separator: ":").map(String.init) }
    var group: String { parts[0] }
    var artifact: String { parts[1] }
    var key: String { "\(group):\(artifact)" + (parts.count > 3 ? ":\(parts[3])" : "") }
    var isNative: Bool { natives != nil || (parts.count > 3 && parts[3].hasPrefix("natives")) }

    /// group:artifact:version[:classifier][@ext] -> путь в maven-репозитории.
    var mavenPath: String {
        let ext = name.contains("@") ? String(name.split(separator: "@")[1]) : "jar"
        let classifier = parts.count > 3 ? "-\(parts[3])" : ""
        return "\(group.replacingOccurrences(of: ".", with: "/"))/\(artifact)/\(parts[2])/\(artifact)-\(parts[2])\(classifier).\(ext)"
    }

    var download: Download? {
        if let artifact = downloads?.artifact, !artifact.url.isEmpty {
            return Download(url: artifact.url, sha1: artifact.sha1, size: artifact.size, path: artifact.path ?? mavenPath)
        }
        if downloads?.artifact != nil { return nil } // пустой url: файл создаёт установщик Forge
        let base = url ?? "https://libraries.minecraft.net/"
        return Download(url: (base.hasSuffix("/") ? base : base + "/") + mavenPath, sha1: sha1, size: size, path: mavenPath)
    }
}

struct VersionInfo: Codable {
    struct Arguments: Codable { var game: [Argument]?; var jvm: [Argument]? }
    struct AssetIndexRef: Codable { var id: String; var url: URL; var sha1: String? }
    struct JavaVersion: Codable { var majorVersion: Int }

    var id: String
    var inheritsFrom: String?
    var type: String?
    var mainClass: String?
    var minecraftArguments: String?
    var arguments: Arguments?
    var assetIndex: AssetIndexRef?
    var assets: String?
    var downloads: [String: Download]?
    var libraries: [Library]?
    var javaVersion: JavaVersion?

    /// Склейка с родительской версией (Fabric, Quilt, Forge кладут только разницу).
    func merged(onto parent: VersionInfo) -> VersionInfo {
        var result = parent
        result.id = id
        result.type = type ?? parent.type
        result.mainClass = mainClass ?? parent.mainClass
        result.minecraftArguments = minecraftArguments ?? parent.minecraftArguments
        result.libraries = (libraries ?? []) + (parent.libraries ?? [])
        result.javaVersion = javaVersion ?? parent.javaVersion
        result.inheritsFrom = nil
        if let child = arguments {
            result.arguments = Arguments(
                game: (parent.arguments?.game ?? []) + (child.game ?? []),
                jvm: (parent.arguments?.jvm ?? []) + (child.jvm ?? []))
        }
        return result
    }
}

struct AssetIndex: Decodable {
    struct Object: Decodable { let hash: String; let size: Int }
    let objects: [String: Object]
    let virtual: Bool?
    let mapToResources: Bool?

    enum CodingKeys: String, CodingKey { case objects, virtual, mapToResources = "map_to_resources" }
}
