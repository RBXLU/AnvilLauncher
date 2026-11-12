import CryptoKit
import Foundation
import Security

struct Account: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case microsoft, offline }
    var id: String { uuid }
    var kind: Kind
    var username: String
    var uuid: String
    var accessToken = "0"
    var xuid = "0"
    var expiresAt: Date?

    static func offline(_ name: String) -> Account {
        // Как у ванильного сервера: UUID v3 от "OfflinePlayer:<ник>".
        var bytes = Array(Insecure.MD5.hash(data: Data("OfflinePlayer:\(name)".utf8)))
        bytes[6] = bytes[6] & 0x0f | 0x30
        bytes[8] = bytes[8] & 0x3f | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return Account(kind: .offline, username: name, uuid: hex)
    }
}

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [Account] = []

    init() {
        if let data = Keychain.read("accounts") {
            accounts = (try? JSONDecoder().decode([Account].self, from: data)) ?? []
        }
    }

    var selected: Account? {
        accounts.first { $0.id == AppSettings.shared.selectedAccount } ?? accounts.first
    }

    func upsert(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        AppSettings.shared.selectedAccount = account.id
        save()
    }

    func remove(_ account: Account) {
        accounts.removeAll { $0.id == account.id }
        Keychain.delete("refresh.\(account.id)")
        save()
    }

    /// Обновляет токен Minecraft, если он истёк. Офлайн-аккаунты возвращаются как есть.
    func refreshed(_ account: Account) async throws -> Account {
        guard account.kind == .microsoft, (account.expiresAt ?? .distantPast) < Date().addingTimeInterval(300) else { return account }
        guard let token = Keychain.read("refresh.\(account.id)").map({ String(decoding: $0, as: UTF8.self) }) else {
            throw LauncherError("Сессия Microsoft истекла, войдите заново")
        }
        let fresh = try await MicrosoftAuth.login(refreshToken: token)
        upsert(fresh)
        return fresh
    }

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) { Keychain.write("accounts", data) }
    }
}

/// Цепочка входа: Microsoft OAuth -> Xbox Live -> XSTS -> Minecraft Services.
enum MicrosoftAuth {
    static let clientID = "00000000402b5328"
    static let redirect = "https://login.live.com/oauth20_desktop.srf"
    static let scope = "service::user.auth.xboxlive.com::MBI_SSL"

    static var authorizeURL: URL {
        var c = URLComponents(string: "https://login.live.com/oauth20_authorize.srf")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return c.url!
    }

    private struct MSToken: Decodable {
        let access_token: String
        let refresh_token: String
    }

    static func login(code: String) async throws -> Account {
        try await finish(token(["code": code, "grant_type": "authorization_code"]))
    }

    static func login(refreshToken: String) async throws -> Account {
        try await finish(token(["refresh_token": refreshToken, "grant_type": "refresh_token"]))
    }

    private static func token(_ params: [String: String]) async throws -> MSToken {
        var form = params
        form["client_id"] = clientID
        form["redirect_uri"] = redirect
        form["scope"] = scope
        return try await HTTP.post(MSToken.self, to: URL(string: "https://login.live.com/oauth20_token.srf")!, form: form)
    }

    private static func finish(_ ms: MSToken) async throws -> Account {
        struct XboxToken: Decodable {
            struct Claims: Decodable { let xui: [[String: String]] }
            let Token: String
            let DisplayClaims: Claims
        }
        let xbl = try await HTTP.post(XboxToken.self, to: URL(string: "https://user.auth.xboxlive.com/user/authenticate")!, json: [
            "Properties": ["AuthMethod": "RPS", "SiteName": "user.auth.xboxlive.com", "RpsTicket": ms.access_token],
            "RelyingParty": "http://auth.xboxlive.com", "TokenType": "JWT",
        ] as [String: Any])
        let xsts: XboxToken
        do {
            xsts = try await HTTP.post(XboxToken.self, to: URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!, json: [
                "Properties": ["SandboxId": "RETAIL", "UserTokens": [xbl.Token]] as [String: Any],
                "RelyingParty": "rp://api.minecraftservices.com/", "TokenType": "JWT",
            ] as [String: Any])
        } catch {
            throw LauncherError("Xbox Live отказал во входе. Проверьте, что у аккаунта есть профиль Xbox и он не детский.")
        }
        let uhs = xsts.DisplayClaims.xui.first?["uhs"] ?? ""

        struct MCToken: Decodable { let access_token: String; let expires_in: Int }
        let mc = try await HTTP.post(MCToken.self, to: URL(string: "https://api.minecraftservices.com/authentication/login_with_xbox")!,
                                     json: ["identityToken": "XBL3.0 x=\(uhs);\(xsts.Token)"])

        struct Profile: Decodable { let id: String; let name: String }
        var request = URLRequest(url: URL(string: "https://api.minecraftservices.com/minecraft/profile")!)
        request.setValue("Bearer \(mc.access_token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await HTTP.session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LauncherError("На этом аккаунте не куплена Minecraft: Java Edition")
        }
        let profile = try JSONDecoder().decode(Profile.self, from: data)

        let account = Account(kind: .microsoft, username: profile.name, uuid: profile.id, accessToken: mc.access_token,
                              xuid: xsts.DisplayClaims.xui.first?["xid"] ?? "0",
                              expiresAt: Date().addingTimeInterval(TimeInterval(mc.expires_in)))
        Keychain.write("refresh.\(account.id)", Data(ms.refresh_token.utf8))
        return account
    }
}

enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.anvil.launcher", kSecAttrAccount as String: key]
    }

    static func write(_ key: String, _ data: Data) {
        SecItemDelete(query(key) as CFDictionary)
        var q = query(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(_ key: String) -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        var result: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess ? result as? Data : nil
    }

    static func delete(_ key: String) { SecItemDelete(query(key) as CFDictionary) }
}
