import SwiftUI
import SBBender
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.applicationIconImage = AppIcon.generate()
    }
}

@main
struct SBBenderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            SidebarView()
                .environment(appState)
                .task { await appState.bootstrap() }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 800)
    }
}
