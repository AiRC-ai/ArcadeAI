import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        TempestRuntimeController.shared.terminateForAppExit()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        TempestRuntimeController.shared.terminateForAppExit()
    }
}

@main
struct TempestAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        MLXLearnerSelfTest.runIfRequested()
        AIParitySelfTest.runIfRequested()
    }

    var body: some Scene {
        WindowGroup("Tempest AI") {
            ContentView()
                .frame(
                    minWidth: 1024,
                    idealWidth: 1280,
                    maxWidth: .infinity,
                    minHeight: 640,
                    idealHeight: 800,
                    maxHeight: .infinity
                )
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
