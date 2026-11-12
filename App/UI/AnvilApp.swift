import SwiftUI

struct AnvilApp: App {
    @StateObject private var state = AppState()
    @StateObject private var instances = InstanceStore()
    @StateObject private var accounts = AccountStore()

    init() {
        Paths.prepare()
        Demo.seed()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(instances)
                .environmentObject(accounts)
                .environmentObject(AppSettings.shared)
                .preferredColorScheme(.dark)
                .tint(.green)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState
    @SceneStorage("tab") private var tab = Demo.initialTab

    var body: some View {
        if let request = state.running {
            GameScreen(request: request)
                .ignoresSafeArea()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
        } else {
            TabView(selection: $tab) {
                InstancesView().tabItem { Label("Сборки", systemImage: "square.stack.3d.up") }.tag(0)
                ModBrowserView(instance: nil).tabItem { Label("Modrinth", systemImage: "magnifyingglass") }.tag(1)
                AccountsView().tabItem { Label("Аккаунты", systemImage: "person.crop.circle") }.tag(2)
                SettingsView().tabItem { Label("Настройки", systemImage: "gearshape") }.tag(3)
            }
            .onAppear {
                switch Demo.screen {
                case "game": state.running = LaunchRequest(args: [], isInstaller: false)
                case "jit": state.waitingForJIT = LaunchRequest(args: [], isInstaller: false)
                default: break
                }
            }
            .overlay(alignment: .bottom) { ProgressBanner(progress: state.progress) }
            .sheet(item: $state.waitingForJIT) { JITWaitView(request: $0) }
            .sheet(isPresented: Binding(get: { state.crashLog != nil }, set: { if !$0 { state.crashLog = nil } })) {
                CrashLogView(log: state.crashLog ?? "")
            }
            .alert("Ошибка", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(state.error ?? "")
            }
        }
    }
}

/// Показывается после того, как игра закрыла приложение: последние строки лога и кнопка «Поделиться».
struct CrashLogView: View {
    let log: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(log)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Игра закрылась")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(items: [GameLauncher.logFile] + [GameLauncher.crashReport()].compactMap { $0 }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

struct GameScreen: UIViewControllerRepresentable {
    let request: LaunchRequest
    func makeUIViewController(context: Context) -> GameViewController {
        GameViewController(args: request.args, isInstaller: request.isInstaller)
    }
    func updateUIViewController(_ controller: GameViewController, context: Context) {}
}

struct ProgressBanner: View {
    @ObservedObject var progress: TaskProgress

    var body: some View {
        if progress.isRunning {
            VStack(alignment: .leading, spacing: 6) {
                Text(progress.title.isEmpty ? "Подготовка…" : progress.title).font(.footnote.weight(.semibold))
                if progress.total > 0 {
                    ProgressView(value: progress.fraction)
                    Text("\(progress.done) из \(progress.total)").font(.caption2).foregroundStyle(.secondary)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
            .padding(.bottom, 56)
        }
    }
}

/// Ждём, пока StikDebug (или другой отладчик) включит JIT, и сразу продолжаем запуск.
struct JITWaitView: View {
    let request: LaunchRequest
    @EnvironmentObject private var state: AppState
    @State private var status = JIT.status
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(status.debugged ? "JIT включён" : "JIT выключен",
                          systemImage: status.debugged ? "checkmark.seal.fill" : "xmark.seal")
                        .foregroundStyle(status.debugged ? .green : .orange)
                    if status.debugged && JIT.needsTXMWorkaround {
                        Label(status.debuggerAttached ? "Отладчик подключён" : "Отладчик должен оставаться подключённым",
                              systemImage: "link")
                    }
                }
                Section("Как включить") {
                    Text("1. Откройте StikDebug (или SideStore → Enable JIT) и выберите Anvil.")
                    Text("2. На iOS 26 назначьте Anvil скрипт Universal JIT в StikDebug: долгое нажатие на приложение → Assign Script.")
                    Text("3. Вернитесь сюда: запуск продолжится сам.")
                }
                Section {
                    ProgressView("Ожидание JIT…")
                }
            }
            .navigationTitle("Нужен JIT")
            .toolbar { Button("Отмена") { state.waitingForJIT = nil } }
        }
        .onReceive(timer) { _ in
            status = JIT.status
            if JIT.isReady {
                state.waitingForJIT = nil
                state.running = request
            }
        }
    }
}

/// Запуск SwiftUI из main.c.
@_cdecl("anvil_swift_main")
func anvilSwiftMain() -> Int32 {
    AnvilApp.main()
    return 0
}
