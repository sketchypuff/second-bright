import SwiftUI
import AppKit
import SecondBrightCore

@main
struct SecondBrightApp: App {

    @State private var controller: BrightnessController
    private let watcher: DisplayWatcher

    init() {
        // `--diagnose` short-circuits before any UI exists, so it stays usable
        // when the GUI is the thing misbehaving.
        if CommandLine.arguments.contains("--diagnose") {
            Diagnostics.run()
            exit(0)
        }

        let controller = BrightnessController()
        let watcher = DisplayWatcher()
        _controller = State(initialValue: controller)
        self.watcher = watcher

        // Start at launch rather than when the popover first opens: the icon has
        // to show the right state immediately, and a remembered brightness must
        // be reapplied on login without the user clicking anything.
        Task { @MainActor in
            Lifecycle.shared.start(controller: controller, watcher: watcher)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            BrightnessPopover(controller: controller)
        } label: {
            Image(systemName: controller.mode == .unavailable
                  ? "sun.max.trianglebadge.exclamationmark"
                  : "sun.max")
        }
        // `.window` is what turns the menu bar item into a real popover able to
        // host a draggable slider; the default `.menu` style cannot.
        .menuBarExtraStyle(.window)
    }
}

/// Wires up display detection and guarantees gamma is handed back on quit.
///
/// Gamma is a system-wide setting that outlives the process: exiting without
/// restoring it leaves the monitor dim with nothing on screen to explain why.
@MainActor
final class Lifecycle {
    static let shared = Lifecycle()
    private var started = false

    func start(controller: BrightnessController, watcher: DisplayWatcher) {
        guard !started else { return }
        started = true

        controller.refresh()
        watcher.start { controller.refresh() }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { controller.shutdown() }
        }
    }
}
