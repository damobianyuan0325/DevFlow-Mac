import SwiftUI
import AppKit

@main
struct DevFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup("DevFlow") {
            ContentView().environmentObject(store)
                .frame(minWidth: 1020, minHeight: 660)
                .alert("需要留意", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                    Button("知道了") { store.errorMessage = nil }
                } message: { Text(store.errorMessage ?? "") }
        }
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("接入开发会话…") { store.connectDevelopmentSession() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(store.isImporting)
                Button("导入项目资料…") { store.importProject() }.keyboardShortcut("o")
                    .disabled(store.isImporting)
                Button("刷新当前项目") { store.refreshSelected() }.keyboardShortcut("r")
                    .disabled(store.selectedProject == nil || store.selectedProject?.isSample == true || store.isImporting)
                Button("导出当前记录…") { store.exportProject() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
