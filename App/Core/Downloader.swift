import CryptoKit
import Foundation

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "AnvilLauncher/0.1 (iOS)"]
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static func data(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try check(response, url)
        return data
    }

    static func json<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        try decoder.decode(T.self, from: try await data(url))
    }

    static func post<T: Decodable>(_ type: T.Type, to url: URL, json body: Any? = nil,
                                   form: [String: String]? = nil, headers: [String: String] = [:]) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let form {
            var components = URLComponents()
            components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = Data((components.percentEncodedQuery ?? "").utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: request)
        try check(response, url)
        return try decoder.decode(T.self, from: data)
    }

    private static func check(_ response: URLResponse, _ url: URL) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LauncherError("HTTP \(http.statusCode): \(url.absoluteString)")
        }
    }
}

struct LauncherError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct DownloadTask: Hashable {
    let url: URL
    let destination: URL
    var sha1: String?
    var size: Int?
}

@MainActor
final class TaskProgress: ObservableObject {
    @Published var title = ""
    @Published var done = 0
    @Published var total = 0
    @Published var isRunning = false

    var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
}

enum Downloader {
    /// Качает пачку файлов параллельно. Уже скачанные файлы с правильным размером пропускает.
    static func run(_ tasks: [DownloadTask], title: String, progress: TaskProgress, parallel: Int = 16) async throws {
        let pending = Array(Set(tasks)).filter { !isValid($0) }
        await MainActor.run {
            progress.title = title
            progress.done = 0
            progress.total = pending.count
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = pending.makeIterator()
            for _ in 0..<min(parallel, pending.count) {
                if let task = iterator.next() { group.addTask { try await fetch(task) } }
            }
            while try await group.next() != nil {
                await MainActor.run { progress.done += 1 }
                if let task = iterator.next() { group.addTask { try await fetch(task) } }
            }
        }
    }

    private static func isValid(_ task: DownloadTask) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: task.destination.path) else { return false }
        guard let size = task.size else { return true }
        return (attrs[.size] as? Int) == size
    }

    static func fetch(_ task: DownloadTask, attempts: Int = 3) async throws {
        for attempt in 1...attempts {
            do {
                let (temp, response) = try await HTTP.session.download(from: task.url)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    throw LauncherError("HTTP \(http.statusCode): \(task.url.lastPathComponent)")
                }
                if let sha1 = task.sha1, try sha1Hex(of: temp) != sha1.lowercased() {
                    throw LauncherError("Неверная контрольная сумма: \(task.url.lastPathComponent)")
                }
                let fm = FileManager.default
                try fm.createDirectory(at: task.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? fm.removeItem(at: task.destination)
                try fm.moveItem(at: temp, to: task.destination)
                return
            } catch where attempt < attempts {
                try await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
            }
        }
    }

    static func sha1Hex(of file: URL) throws -> String {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        return Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
