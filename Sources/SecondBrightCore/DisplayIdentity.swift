import Foundation
import CoreGraphics
import AppKit

/// A stable handle on a physical display.
///
/// The target is chosen by "not built-in", never by macOS's main-display flag:
/// on this Mac the external monitor *is* the main display, so keying off
/// `CGMainDisplayID` would drive exactly the wrong screen.
public struct DisplayIdentity: Equatable {
    public let displayID: CGDirectDisplayID
    public let name: String
    /// Survives replugging and reboots, so a saved brightness can be matched back
    /// to the monitor it came from.
    public let key: String

    public static func externalDisplays() -> [DisplayIdentity] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        return ids.filter { CGDisplayIsBuiltin($0) == 0 }.map { id in
            DisplayIdentity(displayID: id, name: name(for: id), key: key(for: id))
        }
    }

    /// The single external display this app manages. Multi-monitor is out of scope.
    public static func primaryExternal() -> DisplayIdentity? {
        externalDisplays().first
    }

    public static func key(for id: CGDirectDisplayID) -> String {
        "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
    }

    /// The `NSScreen` this display is presented as, if AppKit currently lists it.
    ///
    /// Looked up live rather than stored: screens are replaced wholesale on
    /// reconfiguration, so a cached one goes stale on the first unplug.
    public var screen: NSScreen? { Self.screen(for: displayID) }

    public static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    /// `NSScreen` already resolves the marketing name ("LG ULTRAFINE"); walking the
    /// IORegistry by hand to rediscover it is more code and less reliable.
    private static func name(for id: CGDirectDisplayID) -> String {
        screen(for: id)?.localizedName ?? "External display"
    }
}
