import Foundation
import CoreGraphics

/// Notifies when displays are attached, removed, or wake up.
///
/// Monitors routinely forget their brightness across sleep and unplugging, so the
/// app has to notice and reapply rather than trusting its last write to have stuck.
@MainActor
public final class DisplayWatcher {

    private static var handler: (() -> Void)?
    private var registered = false

    public init() {}

    public func start(onChange: @escaping () -> Void) {
        guard !registered else { return }
        Self.handler = onChange
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            // Only react once the change has settled; the "begin" pass fires
            // before the display list is accurate.
            guard !flags.contains(.beginConfigurationFlag) else { return }
            let interesting: CGDisplayChangeSummaryFlags = [
                .addFlag, .removeFlag, .enabledFlag, .disabledFlag, .setModeFlag,
            ]
            guard !flags.intersection(interesting).isEmpty else { return }
            Task { @MainActor in
                // Monitors need a moment after reconnecting before they accept
                // commands; going straight at them tends to be ignored.
                try? await Task.sleep(for: .seconds(2))
                DisplayWatcher.handler?()
            }
        }, nil)
        registered = true
    }
}
