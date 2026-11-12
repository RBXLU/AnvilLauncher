import Foundation

/// Демо-режим для скриншотов в симуляторе: `-anvilDemo <экран>` в аргументах запуска.
/// В релизной сборке выключен, чтобы случайно не подменить данные пользователя.
enum Demo {
    static var screen: String? {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "anvilDemo")
        #else
        return nil
        #endif
    }

    static var initialTab: Int {
        ["modrinth": 1, "accounts": 2, "settings": 3][screen ?? ""] ?? 0
    }

    /// Заполняет сборки, моды и аккаунты до того, как их прочитают хранилища.
    static func seed() {
        guard screen != nil else { return }
        let fm = FileManager.default
        let survival = Instance(name: "Выживание с друзьями", minecraftVersion: "1.21.4", loader: .fabric,
                                loaderVersion: "0.16.10", versionID: "fabric-loader-0.16.10-1.21.4",
                                memoryMB: 3072, lastPlayed: Date())
        let instances = [
            survival,
            Instance(name: "Create: механизмы", minecraftVersion: "1.20.1", loader: .forge, loaderVersion: "1.20.1-47.3.0",
                     versionID: "1.20.1-forge-47.3.0", lastPlayed: Date().addingTimeInterval(-86_400)),
            Instance(name: "Ванилла", minecraftVersion: "1.21.4", versionID: "1.21.4", lastPlayed: Date().addingTimeInterval(-172_800)),
            Instance(name: "NeoForge тесты", minecraftVersion: "1.21.1", loader: .neoforge, loaderVersion: "21.1.77",
                     versionID: "neoforge-21.1.77"),
            Instance(name: "Старая школа", minecraftVersion: "1.12.2", loader: .forge, loaderVersion: "1.12.2-14.23.5.2860",
                     versionID: "1.12.2-forge-14.23.5.2860"),
        ]
        try? JSONEncoder().encode(instances).write(to: Paths.root.appending(path: "instances.json"))

        try? fm.createDirectory(at: survival.modsDirectory, withIntermediateDirectories: true)
        for mod in ["fabric-api-0.114.0+1.21.4.jar", "sodium-fabric-0.6.6+mc1.21.4.jar", "iris-fabric-1.8.5+mc1.21.4.jar",
                    "lithium-fabric-0.14.7+mc1.21.4.jar", "modmenu-13.0.0.jar", "journeymap-1.21.4-6.0.0.jar.disabled"] {
            fm.createFile(atPath: survival.modsDirectory.appending(path: mod).path, contents: Data())
        }

        let accounts = [Account.offline("Steve"), Account.offline("Alex")]
        if let data = try? JSONEncoder().encode(accounts) { Keychain.write("accounts", data) }
        AppSettings.shared.selectedAccount = accounts[0].id
    }
}
