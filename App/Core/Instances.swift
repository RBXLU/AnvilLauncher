import Foundation
import SwiftUI

enum Loader: String, Codable, CaseIterable, Identifiable {
    case vanilla, fabric, quilt, forge, neoforge
    var id: String { rawValue }
    var title: String {
        switch self {
        case .vanilla: return "Vanilla"
        case .fabric: return "Fabric"
        case .quilt: return "Quilt"
        case .forge: return "Forge"
        case .neoforge: return "NeoForge"
        }
    }
    /// Имя загрузчика в API Modrinth.
    var modrinthName: String? { self == .vanilla ? nil : rawValue }
}

enum Renderer: String, Codable, CaseIterable, Identifiable {
    case auto, mobileGlues, gl4es
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Авто"
        case .mobileGlues: return "MobileGlues (1.17+)"
        case .gl4es: return "gl4es (до 1.16.5)"
        }
    }
    func library(for info: VersionInfo) -> String {
        switch self {
        case .mobileGlues: return "libmobileglues.dylib"
        case .gl4es: return "libgl4es_114.dylib"
        case .auto: return (info.javaVersion?.majorVersion ?? 8) >= 16 ? "libmobileglues.dylib" : "libgl4es_114.dylib"
        }
    }
}

struct Instance: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var minecraftVersion: String
    var loader: Loader = .vanilla
    var loaderVersion: String?
    /// Какой json запускать: у ванилы совпадает с версией игры, у модлоадеров свой.
    var versionID: String
    var memoryMB: Int?
    var renderer: Renderer?
    var jvmArgs = ""
    var lastPlayed: Date?

    var directory: URL { Paths.instances.appending(path: id.uuidString) }
    var modsDirectory: URL { directory.appending(path: "mods") }

    func folder(_ name: String) -> URL {
        let url = directory.appending(path: name)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@MainActor
final class InstanceStore: ObservableObject {
    @Published var instances: [Instance] = [] { didSet { save() } }
    private let file = Paths.root.appending(path: "instances.json")

    init() {
        if let data = try? Data(contentsOf: file) {
            instances = (try? JSONDecoder().decode([Instance].self, from: data)) ?? []
        }
    }

    func add(_ instance: Instance) {
        try? FileManager.default.createDirectory(at: instance.modsDirectory, withIntermediateDirectories: true)
        instances.append(instance)
    }

    func update(_ instance: Instance) {
        if let i = instances.firstIndex(where: { $0.id == instance.id }) { instances[i] = instance }
    }

    func remove(_ instance: Instance) {
        instances.removeAll { $0.id == instance.id }
        try? FileManager.default.removeItem(at: instance.directory)
    }

    private func save() {
        try? JSONEncoder().encode(instances).write(to: file, options: .atomic)
    }
}

/// Глобальные настройки. Хранятся в UserDefaults, чтобы ими можно было пользоваться из UIKit-части.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let physicalMemoryMB = Int(ProcessInfo.processInfo.physicalMemory >> 20)

    @AppStorage("memoryMB") var memoryMB = max(1024, physicalMemoryMB / 4)
    @AppStorage("renderer") var renderer = Renderer.auto
    @AppStorage("resolutionScale") var resolutionScale = 0.75
    @AppStorage("sensitivity") var sensitivity = 1.0
    @AppStorage("controlsOpacity") var controlsOpacity = 0.6
    @AppStorage("hideControlsWithInputDevice") var hideControlsWithInputDevice = true
    @AppStorage("gamepadDeadzone") var gamepadDeadzone = 0.15
    @AppStorage("selectedAccount") var selectedAccount = ""
    @AppStorage("jvmArgs") var jvmArgs = ""
}
