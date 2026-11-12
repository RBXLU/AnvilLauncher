import SwiftUI
import WebKit

struct AccountsView: View {
    @EnvironmentObject private var accounts: AccountStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var state: AppState
    @State private var microsoftLogin = false
    @State private var offlineName = ""
    @State private var askOffline = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(accounts.accounts) { account in
                    Button {
                        settings.selectedAccount = account.id
                    } label: {
                        HStack {
                            AsyncImage(url: URL(string: "https://mc-heads.net/avatar/\(account.uuid)/64")) {
                                $0.resizable().interpolation(.none)
                            } placeholder: { Color.gray.opacity(0.3) }
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading) {
                                Text(account.username).font(.headline)
                                Text(account.kind == .microsoft ? "Microsoft" : "Офлайн").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if accounts.selected?.id == account.id { Image(systemName: "checkmark").foregroundStyle(.green) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { $0.map { accounts.accounts[$0] }.forEach(accounts.remove) }

                Section {
                    Button("Войти через Microsoft", systemImage: "person.badge.key") { microsoftLogin = true }
                    Button("Офлайн-аккаунт", systemImage: "person") { askOffline = true }
                } footer: {
                    Text("Для игры на лицензионных серверах нужен аккаунт Microsoft с купленной Java Edition.")
                }
            }
            .navigationTitle("Аккаунты")
            .sheet(isPresented: $microsoftLogin) {
                MicrosoftLoginView { code in
                    microsoftLogin = false
                    state.perform { accounts.upsert(try await MicrosoftAuth.login(code: code)) }
                }
            }
            .alert("Ник игрока", isPresented: $askOffline) {
                TextField("Steve", text: $offlineName).textInputAutocapitalization(.never)
                Button("Добавить") {
                    let name = offlineName.trimmingCharacters(in: .whitespaces)
                    if (3...16).contains(name.count) { accounts.upsert(.offline(name)) }
                    offlineName = ""
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("От 3 до 16 символов")
            }
        }
    }
}

/// Страница входа Microsoft. Ловим редирект на oauth20_desktop.srf и забираем code.
struct MicrosoftLoginView: UIViewRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: MicrosoftAuth.authorizeURL))
        return web
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url, url.absoluteString.hasPrefix(MicrosoftAuth.redirect) else {
                return decisionHandler(.allow)
            }
            decisionHandler(.cancel)
            if let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value {
                onCode(code)
            }
        }
    }
}
