import SwiftUI

/// Что запускаем: игру или установщик Forge/NeoForge.
struct LaunchRequest: Identifiable {
    let id = UUID()
    let args: [String]
    let isInstaller: Bool
}

@MainActor
final class AppState: ObservableObject {
    @Published var running: LaunchRequest?
    @Published var waitingForJIT: LaunchRequest?
    @Published var error: String?
    /// Хвост лога, если прошлый запуск игры закончился закрытием приложения.
    @Published var crashLog = GameLauncher.takeCrashLog()
    let progress = TaskProgress()

    func play(_ instance: Instance, accounts: AccountStore, store: InstanceStore) {
        guard let account = accounts.selected else {
            error = "Добавьте аккаунт на вкладке «Аккаунты»"
            return
        }
        perform {
            let fresh = try await accounts.refreshed(account)
            let args = try await GameLauncher.gameArguments(instance, account: fresh, progress: self.progress)
            var played = instance
            played.lastPlayed = Date()
            store.update(played)
            self.launch(LaunchRequest(args: args, isInstaller: false))
        }
    }

    /// Ставит выбранный загрузчик. Fabric и Quilt готовы сразу, Forge и NeoForge требуют запуска установщика.
    func installLoader(for instance: Instance, store: InstanceStore) {
        perform { try await self.loaderStep(instance, store: store) }
    }

    func loaderStep(_ instance: Instance, store: InstanceStore) async throws {
        guard let version = instance.loaderVersion, instance.loader != .vanilla else { return }
        var updated = instance
        switch try await LoaderInstaller.install(instance.loader, version: version, mc: instance.minecraftVersion) {
        case .ready(let id):
            updated.versionID = id
            store.update(updated)
        case .needsInstaller(let jar, let id):
            updated.versionID = id
            store.update(updated)
            _ = try await VersionManager.install(instance.minecraftVersion, progress: progress)
            launch(LaunchRequest(args: try GameLauncher.installerArguments(jar), isInstaller: true))
        }
    }

    func launch(_ request: LaunchRequest) {
        if JIT.isReady { running = request } else { waitingForJIT = request }
    }

    func perform(_ work: @escaping () async throws -> Void) {
        guard !progress.isRunning else { return }
        progress.isRunning = true
        Task {
            defer { progress.isRunning = false }
            do { try await work() } catch { self.error = error.localizedDescription }
        }
    }
}
