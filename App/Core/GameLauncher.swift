import Foundation
import UIKit

enum JIT {
    static var status: AnvilJITStatus { anvil_jit_status() }

    /// На iOS 26 JVM работает с зеркальным кодовым кэшем на любом чипе (так же делает Amethyst).
    static var usesMirroredCodeCache: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    /// Чипы с TXM на iOS 26+ не дают RX-страниц даже с CS_DEBUGGED: память под код выдаёт
    /// отладчик через скрипт Universal JIT в StikDebug, поэтому он должен оставаться подключённым.
    static var needsTXMWorkaround: Bool {
        guard #available(iOS 26, *) else { return false }
        return DeviceHasTXM()
    }

    /// Договориться со скриптом StikDebug до старта JVM. Без этого JVM упадёт на первом же JIT-коде.
    static func prepareForJVM() throws {
        guard needsTXMWorkaround else { return }
        guard let url = Bundle.main.url(forResource: "AnvilJIT26", withExtension: "js"),
              let script = try? String(contentsOf: url) else {
            throw LauncherError("В приложении нет AnvilJIT26.js")
        }
        if anvil_jit26_handshake(script) != 0 {
            throw LauncherError("""
                На этом устройстве (TXM) нужен скрипт Universal JIT. В StikDebug долго нажмите на Anvil → \
                Assign Script → Universal JIT, затем снова включите JIT и запустите игру.
                """)
        }
    }

    static var isReady: Bool {
        let s = status
        guard s.debugged else { return false }
        return needsTXMWorkaround ? s.debuggerAttached : true
    }
}

enum GameLauncher {
    static var logFile: URL { Paths.logs.appending(path: "latest.log") }

    /// Forge старых версий называет json иначе, чем мы ожидаем: ищем его по inheritsFrom.
    static func resolveVersionID(_ instance: Instance) -> String? {
        if FileManager.default.fileExists(atPath: Paths.versionJSON(instance.versionID).path) { return instance.versionID }
        guard instance.loader == .forge || instance.loader == .neoforge else { return nil }
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: Paths.versions.path)) ?? []
        return ids.first { id in
            guard id.lowercased().contains(instance.loader.rawValue),
                  let data = try? Data(contentsOf: Paths.versionJSON(id)),
                  let info = try? HTTP.decoder.decode(VersionInfo.self, from: data) else { return false }
            return info.inheritsFrom == instance.minecraftVersion
        }
    }

    @MainActor
    static func gameArguments(_ instance: Instance, account: Account, progress: TaskProgress) async throws -> [String] {
        guard let versionID = resolveVersionID(instance) ?? (instance.loader == .vanilla ? instance.versionID : nil) else {
            throw LauncherError("\(instance.loader.title) ещё не установлен. Откройте сборку и запустите установщик.")
        }
        let info = try await VersionManager.install(versionID, progress: progress)
        let major = info.javaVersion?.majorVersion ?? 8
        guard let javaHome = Paths.runtime(minimum: major) else {
            throw LauncherError("Нет встроенной Java \(major)+. Пересоберите приложение со scripts/fetch-deps.sh")
        }
        let settings = AppSettings.shared
        let renderer = (instance.renderer ?? settings.renderer).library(for: info)
        let gameDir = instance.directory
        try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
        writeMobileDefaults(to: gameDir)

        let legacyLWJGL = VersionManager.usesLegacyLWJGL(info)
        let lwjglJars = ((try? FileManager.default.contentsOfDirectory(atPath: Paths.lwjgl.path)) ?? [])
            .filter { $0.hasSuffix(".jar") && (legacyLWJGL || $0 != "lwjgl-lwjglx.jar") }
            .sorted()
            .map { Paths.lwjgl.appending(path: $0).path }
        let libraryJars = VersionManager.libraries(of: info).map {
            Paths.libraries.appending(path: $0.downloads?.artifact?.path ?? $0.mavenPath).path
        }
        let clientJar = Paths.versionJar(try VersionManager.clientJarID(versionID)).path
        let classpath = ([Paths.glfwShim.path] + lwjglJars + libraryJars + [clientJar]).joined(separator: ":")

        let assetsID = info.assetIndex?.id ?? info.assets ?? "legacy"
        let values: [String: String] = [
            "auth_player_name": account.username,
            "auth_uuid": account.uuid,
            "auth_access_token": account.accessToken,
            "auth_session": "token:\(account.accessToken):\(account.uuid)",
            "auth_xuid": account.xuid,
            "clientid": MicrosoftAuth.clientID,
            "user_type": account.kind == .microsoft ? "msa" : "legacy",
            "user_properties": "{}",
            "version_name": versionID,
            "version_type": info.type ?? "release",
            "game_directory": gameDir.path,
            "assets_root": Paths.assets.path,
            "game_assets": Paths.assets.appending(path: "virtual/\(assetsID)").path,
            "assets_index_name": assetsID,
            "resolution_width": String(Int(UIScreen.main.nativeBounds.height * settings.resolutionScale)),
            "resolution_height": String(Int(UIScreen.main.nativeBounds.width * settings.resolutionScale)),
            "natives_directory": Paths.frameworks.path,
            "library_directory": Paths.libraries.path,
            "classpath_separator": ":",
            "classpath": classpath,
            "launcher_name": "Anvil",
            "launcher_version": "0.1",
        ]
        func substitute(_ arg: String) -> String {
            values.reduce(arg) { $0.replacingOccurrences(of: "${\($1.key)}", with: $1.value) }
        }

        let memory = instance.memoryMB ?? settings.memoryMB
        guard canReserve(megabytes: memory) else {
            throw LauncherError("""
                iOS не даёт выделить \(memory) МБ одним куском. Уменьшите память в настройках \
                (на бесплатном Apple ID обычно работает до 1/4 ОЗУ устройства).
                """)
        }
        var jvm = [
            "\(javaHome.path)/bin/java",
            "-Xms256M", "-Xmx\(memory)M",
            "-XstartOnFirstThread",
            "-XX:+UnlockExperimentalVMOptions",
            "-XX:+DisablePrimordialThreadGuardPages",
            "-Djava.awt.headless=true",
            "-Djava.library.path=\(Paths.frameworks.path)",
            "-Duser.home=\(Paths.root.path)",
            "-Duser.dir=\(gameDir.path)",
            "-Duser.timezone=\(TimeZone.current.identifier)",
            "-Dorg.lwjgl.opengl.libname=\(renderer)",
            "-Dorg.lwjgl.glfw.checkThread0=false",
            "-Dorg.lwjgl.system.allocator=system",
            "-Dlog4j2.formatMsgNoLookups=true",
            "-Danvil.refreshRate=\(UIScreen.main.maximumFramesPerSecond)",
        ]
        jvm += jailedFlags
        jvm += (settings.jvmArgs + " " + instance.jvmArgs).split(separator: " ").map(String.init)

        let mojangJVM = info.arguments?.jvm?.flatMap(\.resolved)
            ?? ["-Djava.library.path=${natives_directory}", "-cp", "${classpath}"]
        jvm += mojangJVM.map(substitute).filter { !$0.hasPrefix("-Djava.library.path") && $0 != "-XstartOnFirstThread" }

        let game = info.arguments?.game?.flatMap(\.resolved)
            ?? (info.minecraftArguments ?? "").split(separator: " ").map(String.init)
        // У современных версий --width/--height уже приходят через has_custom_resolution.
        let size = info.arguments == nil ? ["--width", values["resolution_width"]!, "--height", values["resolution_height"]!] : []
        return jvm + [info.mainClass ?? "net.minecraft.client.main.Main"] + game.map(substitute) + size
    }

    /// Стартовые настройки игры для телефона. Пишутся только в новую сборку: свои настройки игрока не трогаем.
    /// Неизвестные ключи старые версии просто пропускают.
    static func writeMobileDefaults(to gameDir: URL) {
        let file = gameDir.appending(path: "options.txt")
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        let options = [
            "renderDistance:6", "simulationDistance:5", "graphicsMode:0", "fancyGraphics:false",
            "entityShadows:false", "particles:1", "mipmapLevels:0", "biomeBlendRadius:0",
            "ao:false", "maxFps:60", "enableVsync:true", "prioritizeChunkUpdates:0", "onboardAccessibility:false",
        ]
        try? (options.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    static func installerArguments(_ jar: URL) throws -> [String] {
        guard let javaHome = Paths.runtime(minimum: 21) ?? Paths.runtime(minimum: 17) ?? Paths.runtime(minimum: 8) else {
            throw LauncherError("Нет встроенной Java для запуска установщика")
        }
        return ["\(javaHome.path)/bin/java", "-Xmx1024M", "-Djava.awt.headless=true",
                "-XX:+UnlockExperimentalVMOptions", "-XX:+DisablePrimordialThreadGuardPages",
                "-Duser.home=\(Paths.root.path)", "-Duser.dir=\(Paths.root.path)"]
            + jailedFlags + ["-jar", jar.path, "--installClient", Paths.root.path]
    }

    /// Флаги, без которых HotSpot падает на старте в «тюрьме» iOS.
    private static var jailedFlags: [String] {
        // Без entitlement extended-virtual-addressing (бесплатный Apple ID) iOS не даёт
        // зарезервировать 1 ГБ под сжатое пространство классов, и JVM аварийно завершается.
        var flags = ["-XX:-UseCompressedClassPointers"]
        if JIT.usesMirroredCodeCache { flags.append("-XX:+MirrorMappedCodeCache") }
        return flags
    }

    /// Проверяем заранее, что под кучу найдётся непрерывный кусок адресного пространства.
    static func canReserve(megabytes: Int) -> Bool {
        let size = megabytes << 20
        // MAP_FAILED в Swift не импортируется: это (void *)-1.
        guard let map = mmap(nil, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0),
              Int(bitPattern: map) != -1 else { return false }
        return munmap(map, size) == 0
    }

    /// Пока игра идёт, лежит этот файл. Если приложение открылось, а он остался — игра упала.
    static var runningMarker: URL { Paths.logs.appending(path: ".running") }

    /// Хвост лога прошлого запуска, если тот закончился вылетом.
    static func takeCrashLog() -> String? {
        let fm = FileManager.default
        guard let started = (try? fm.attributesOfItem(atPath: runningMarker.path))?[.modificationDate] as? Date else { return nil }
        try? fm.removeItem(at: runningMarker)

        var text = ""
        // Краш-репорт Minecraft начинается с причины и стека — это самое важное.
        if let report = crashReport(since: started), let data = try? Data(contentsOf: report) {
            let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            text += "=== \(report.lastPathComponent) ===\n" + lines.prefix(80).joined(separator: "\n") + "\n\n"
        }
        if let data = try? Data(contentsOf: logFile) {
            let lines = String(decoding: data.suffix(16_000), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
            text += "=== latest.log ===\n" + lines.suffix(60).joined(separator: "\n")
        }
        return text.isEmpty ? "Лог пуст: JVM не успела ничего вывести." : text
    }

    /// Самый свежий краш-репорт из любой сборки, созданный после запуска игры.
    static func crashReport(since date: Date = .distantPast) -> URL? {
        let fm = FileManager.default
        let instances = (try? fm.contentsOfDirectory(at: Paths.instances, includingPropertiesForKeys: nil)) ?? []
        let reports = instances.flatMap {
            (try? fm.contentsOfDirectory(at: $0.appending(path: "crash-reports"), includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        }
        func modified(_ url: URL) -> Date { (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
        return reports.filter { modified($0) >= date }.max { modified($0) < modified($1) }
    }

    /// Запускает JVM в этом же процессе. Вернуться из неё нельзя: по выходу игры приложение закрывается.
    @MainActor
    static func start(_ args: [String], renderer: String = "libmobileglues.dylib") throws {
        guard let home = args.first.map({ URL(fileURLWithPath: $0).deletingLastPathComponent().deletingLastPathComponent() }) else { return }
        setenv("JAVA_HOME", home.path, 1)
        setenv("ANVIL_EXECUTABLE", Bundle.main.executablePath ?? "", 1)
        setenv("ANVIL_RENDERER", args.first { $0.hasPrefix("-Dorg.lwjgl.opengl.libname=") }?
            .replacingOccurrences(of: "-Dorg.lwjgl.opengl.libname=", with: "") ?? renderer, 1)
        setenv("LIBGL_ES", "3", 1)
        setenv("LIBGL_NORMALIZE", "1", 1)
        setenv("LIBGL_NOINTOVLHACK", "1", 1)
        setenv("HOME", Paths.root.path, 1)
        // Иначе -XstartOnFirstThread уводит игру в главный поток: UIKit замирает, кадры не выводятся.
        // Этот переключатель встроен в libjli из iOS-сборки OpenJDK.
        setenv("HACK_IGNORE_START_ON_FIRST_THREAD", "1", 1)
        // -Duser.dir не меняет текущую папку процесса, а игра и моды пишут по относительным путям
        // (logs/, config/): без chdir они пытаются писать в корень системы.
        if let dir = args.first(where: { $0.hasPrefix("-Duser.dir=") })?.dropFirst("-Duser.dir=".count) {
            FileManager.default.changeCurrentDirectoryPath(String(dir))
        }

        try JIT.prepareForJVM()
        FileManager.default.createFile(atPath: runningMarker.path, contents: nil)

        // Нативная сторона делает свои копии строк, поэтому освобождаем сразу после вызова.
        let cStrings = args.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        let rc = cStrings.map { UnsafePointer($0) }.withUnsafeBufferPointer {
            anvil_launch_jvm(Int32(args.count), $0.baseAddress, logFile.path)
        }
        if rc != 0 { throw LauncherError("Не удалось создать поток JVM (\(rc))") }
    }
}
