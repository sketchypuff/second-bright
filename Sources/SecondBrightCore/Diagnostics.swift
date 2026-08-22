import Foundation
import CoreGraphics
import IOKit

/// Prints what the brightness layer can and cannot see.
///
/// This is the tool to reach for when the slider doesn't move the monitor: it
/// separates the failure into a specific layer instead of just reporting that
/// something didn't work.
public enum Diagnostics {

    public static func run() {
        print("SecondBright diagnostics")
        print(String(repeating: "-", count: 46))

        print("IOAVService symbols resolved : \(DDCService.isSupported)")

        let proxies = DDCService.externalAVServiceProxies()
        print("External AV service nodes    : \(proxies.count)")
        proxies.forEach { IOObjectRelease($0) }

        let displays = DisplayIdentity.externalDisplays()
        print("External displays            : \(displays.count)")
        for display in displays {
            print("  - \(display.name)  id=\(display.displayID)  key=\(display.key)")
            print("    macOS can set backlight   : \(DisplayServices.canChangeBrightness(display.displayID))")
        }

        guard let ddc = DDCService.forExternalDisplay() else {
            print("\nNo AV service could be opened. Falling back to software dimming.")
            return
        }
        print("\nAV service opened.")

        // Distinguishes a dead I2C link from a panel that simply refuses DDC/CI.
        if let edid = ddc.readEDIDHeader() {
            let vendorBits = UInt16(edid[8]) << 8 | UInt16(edid[9])
            let letters = [(vendorBits >> 10) & 0x1F, (vendorBits >> 5) & 0x1F, vendorBits & 0x1F]
                .map { String(UnicodeScalar(UInt8($0) + 64)) }.joined()
            print("EDID read (0x50)             : ok, manufacturer \(letters)")
        } else {
            print("EDID read (0x50)             : FAILED - the I2C link itself is unavailable")
        }

        if let reading = ddc.read(.luminance) {
            let hex = reading.raw.map { String(format: "%02X", $0) }.joined(separator: " ")
            print("DDC luminance (0x37)         : ok, \(reading.current) of \(reading.maximum)")
            print("Raw reply                    : \(hex)")
            print("\nDDC is working: real backlight control is available.")
        } else {
            print("DDC luminance (0x37)         : FAILED")
            print("""

            The display answers EDID but refuses DDC/CI. That usually means DDC/CI \
            is switched off in the monitor's own on-screen menu, or the panel \
            doesn't implement it over this connection. SecondBright will dim the \
            image in software instead. If you enable DDC/CI in the monitor's \
            settings, SecondBright picks it up automatically on the next replug \
            or relaunch.
            """)
        }
    }
}

/// The private brightness API macOS itself uses for external displays.
///
/// Consulted for diagnostics only: when it reports it cannot change a display's
/// brightness, that independently corroborates a DDC failure rather than leaving
/// the cause ambiguous.
enum DisplayServices {
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY
    )

    static func canChangeBrightness(_ id: CGDirectDisplayID) -> Bool {
        guard let handle, let sym = dlsym(handle, "DisplayServicesCanChangeBrightness") else {
            return false
        }
        return unsafeBitCast(sym, to: CanChange.self)(id)
    }
}
