import AppKit
import SwiftUI

@main
struct YanaMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var boot = AppBoot()

    var body: some Scene {
        WindowGroup("Yana", id: "main") {
            BootView(boot: boot)
        }
        .defaultSize(width: 1100, height: 720)
        .commands { AppCommands(model: boot.model) }

        Settings {
            if let model = boot.model {
                SettingsView(model: model)
            } else {
                ProgressView().padding()
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // UI tests render both appearances regardless of the system setting (`-YanaAppearance light|dark`).
        switch UserDefaults.standard.string(forKey: "YanaAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        // CKSyncEngine delivers changes from other Macs through push; it needs the app registered for them.
        if SyncController.hasCloudKitEntitlement { NSApplication.shared.registerForRemoteNotifications() }
    }
}

/// Builds the stores and models once, asynchronously, at launch.
@MainActor @Observable
final class AppBoot {
    private(set) var model: AppModel?
    private(set) var failure: String?
    private var started = false

    func start() async {
        guard !started else { return }
        started = true
        do {
            let (environment, sync) = try await AppEnvironment.make()
            let model = AppModel(environment: environment, sync: sync)
            self.model = model
            await sync.start()
            await model.start()
        } catch {
            failure = error.localizedDescription
        }
    }
}

struct BootView: View {
    let boot: AppBoot

    var body: some View {
        Group {
            if let model = boot.model {
                RootView(model: model)
            } else if let failure = boot.failure {
                ContentUnavailableView("Yana could not open its data", systemImage: "exclamationmark.triangle",
                                       description: Text(failure))
            } else {
                ProgressView()
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .task { await boot.start() }
    }
}
