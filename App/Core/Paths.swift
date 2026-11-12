import Foundation

/// Раскладка файлов повторяет .minecraft, чтобы установщики Forge/NeoForge работали без доработок.
enum Paths {
    static let root: URL = {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return url
    }()
    static let versions = root.appending(path: "versions")
    static let libraries = root.appending(path: "libraries")
    static let assets = root.appending(path: "assets")
    static let instances = root.appending(path: "instances")
    static let logs = root.appending(path: "logs")
    static let bundled = Bundle.main.bundleURL.appending(path: "Bundled")
    static let lwjgl = bundled.appending(path: "lwjgl")
    static let glfwShim = bundled.appending(path: "anvil-glfw.jar")
    static let frameworks = Bundle.main.bundleURL.appending(path: "Frameworks")

    static func versionJSON(_ id: String) -> URL { versions.appending(path: "\(id)/\(id).json") }
    static func versionJar(_ id: String) -> URL { versions.appending(path: "\(id)/\(id).jar") }

    /// Самый младший из встроенных рантаймов, который подходит под требование версии.
    static func runtime(minimum major: Int) -> URL? {
        let dir = bundled.appending(path: "runtimes")
        let available = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .compactMap { Int($0.replacingOccurrences(of: "java-", with: "")) }
            .sorted()
        return available.first { $0 >= major }.map { dir.appending(path: "java-\($0)") }
    }

    static func prepare() {
        for dir in [versions, libraries, assets, instances, logs] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let profiles = root.appending(path: "launcher_profiles.json")
        if !FileManager.default.fileExists(atPath: profiles.path) {
            try? Data(#"{"profiles":{}}"#.utf8).write(to: profiles)
        }
    }
}
