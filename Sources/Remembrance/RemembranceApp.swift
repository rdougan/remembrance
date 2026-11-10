import AppKit
import SwiftUI

@main
struct RemembranceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var service = ServiceController()

    var body: some Scene {
        Window("Remembrance", id: "main") {
            ContentView()
                .environmentObject(service)
                .onAppear { appDelegate.service = service }
        }
        .defaultSize(width: 720, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Service") {
                Button(service.pending != nil ? "Start Now" : "Play Selected") { service.go() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(service.playing != nil)
                Button(service.pending != nil && service.playing == nil ? "Cancel" : "Fade Out") { service.stop() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .disabled(!service.isBusy)
                Button("Stop at Once") { service.stop(fade: 0) }
                    .keyboardShortcut(.escape, modifiers: [.shift])
                    .disabled(!service.isBusy)
                Divider()
                Button("Select Previous") { service.select(-1) }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("Select Next") { service.select(1) }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Divider()
                Button("Start Over") { service.reset() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var service: ServiceController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// REMEMBRANCE_PLAY=<cue id> starts that cue at launch (for testing the sequence).
    /// REMEMBRANCE_SNAPSHOT=<prefix> saves the window to <prefix>-<seconds>.png at each of
    /// REMEMBRANCE_SNAPSHOT_AT (default "2") seconds after launch, for checking the layout
    /// without screen-recording permission.
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = ProcessInfo.processInfo.environment
        if let id = env["REMEMBRANCE_PLAY"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let s = self?.service, let i = s.cues.firstIndex(where: { $0.id == id }) else { return }
                s.start(i)
            }
        }
        guard let prefix = env["REMEMBRANCE_SNAPSHOT"] else { return }
        for t in (env["REMEMBRANCE_SNAPSHOT_AT"] ?? "2").split(separator: ",").compactMap({ Double($0) }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                guard let content = NSApp.windows.first(where: { $0.isVisible })?.contentView,
                      let view = content.superview ?? Optional(content),   // the frame view: title bar included
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: "\(prefix)-\(Int(t)).png"))
            }
        }
    }

    /// Ask before quitting mid-cue, so a stray ⌘Q can't cut off the Last Post.
    @MainActor
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let service, service.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit while audio is playing?"
        alert.informativeText = "The current cue will stop immediately."
        alert.addButton(withTitle: "Keep Playing")
        alert.addButton(withTitle: "Quit")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
