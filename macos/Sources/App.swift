import AppKit
import SwiftUI

@main
struct YouTubeZeroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var library = Library.shared

    var body: some Scene {
        Window("YouTube Zero", id: "main") {
            ContentView()
                .environmentObject(library)
                .task { library.start() }
                .sheet(isPresented: $library.showSignIn) { SignInSheet().environmentObject(library) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                if library.cookieSource == .app {
                    Button("Sign Out of YouTube") { library.signOut() }
                } else {
                    Button("Sign In to YouTube…") { library.showSignIn = true }
                }
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") { library.refreshAll() }.keyboardShortcut("r")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            PlayerModel.current?.savePosition(force: true)
            Library.shared.cancelAll()
        }
    }
}
