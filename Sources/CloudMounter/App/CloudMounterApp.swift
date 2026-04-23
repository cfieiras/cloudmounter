import SwiftUI
import UserNotifications

@main
struct CloudMounterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = AccountStore.shared

    var body: some Scene {
        WindowGroup("CloudMounter") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 720, minHeight: 500)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            MenuBarIcon()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        Task { @MainActor in
            let store = AccountStore.shared
            for account in store.accounts where account.autoMount {
                await RcloneService.shared.mount(account: account)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        let store = AccountStore.shared
        for account in store.accounts where account.isMounted {
            RcloneService.shared.unmountSync(account: account)
        }
    }
}
