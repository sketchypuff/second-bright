import Foundation
import SecondBrightCore

// A deliberately tiny harness. See Package.swift for why this is an executable
// rather than a test target.

var failures = 0
var checks = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    checks += 1
    if condition() {
        print("  ok   \(name)")
    } else {
        print("  FAIL \(name)")
        failures += 1
    }
}

func suite(_ name: String, _ body: () -> Void) {
    print("\(name):")
    body()
    print("")
}

suite("DDC reply parsing") {
    // A well-formed Get VCP Feature Reply: opcode 0x02, result 0, feature 0x10,
    // type, max 0x0064 (100), current 0x0032 (50).
    let good: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00, 0x00]
    let parsed = DDCService.parseReply(good, vcp: .luminance)
    check("reads current from a well-formed reply", parsed?.current == 50)
    check("reads maximum from a well-formed reply", parsed?.maximum == 100)

    // How many leading address bytes a read includes varies, so the parser
    // anchors on the opcode rather than a fixed offset.
    let shifted: [UInt8] = [0x00, 0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x4B, 0x00]
    check("finds the reply at a shifted offset",
          DDCService.parseReply(shifted, vcp: .luminance)?.current == 75)

    // An all-zero buffer is what an unresponsive panel returns. Reading it as a
    // valid zero would make the app believe DDC works and silently do nothing --
    // which is exactly the failure this monitor exhibits.
    check("rejects an all-zero reply",
          DDCService.parseReply([UInt8](repeating: 0, count: 12), vcp: .luminance) == nil)

    let errored: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00, 0x00]
    check("rejects a non-zero result code",
          DDCService.parseReply(errored, vcp: .luminance) == nil)

    let otherFeature: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00, 0x00]
    check("rejects a reply about a different VCP feature",
          DDCService.parseReply(otherFeature, vcp: .luminance) == nil)

    let nonsense: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x0A, 0x00, 0x64, 0x00, 0x00]
    check("rejects current above maximum",
          DDCService.parseReply(nonsense, vcp: .luminance) == nil)
}

suite("Software dimming scale") {
    check("100% leaves gamma untouched",
          abs(GammaDimmer.scale(forPercent: 100) - 1.0) < 0.0001)

    // Zero percent must still leave the screen readable, otherwise the user
    // cannot see the slider they need in order to undo it.
    check("0% stops at the readable floor",
          abs(GammaDimmer.scale(forPercent: 0) - GammaDimmer.minimumScale) < 0.0001)

    let curve = stride(from: 0.0, through: 100.0, by: 5).map(GammaDimmer.scale(forPercent:))
    check("scale increases monotonically", curve == curve.sorted())

    check("out-of-range input is clamped",
          [-50.0, -1.0, 101.0, 500.0].allSatisfy {
              let s = GammaDimmer.scale(forPercent: $0)
              return s >= GammaDimmer.minimumScale && s <= 1.0
          })
}

suite("Persistence keys") {
    // Saved levels are keyed per monitor, so plugging in a different display
    // doesn't inherit the wrong brightness.
    check("key is namespaced per display",
          BrightnessController.defaultsKey(for: "7789-23489-338818") == "brightness.7789-23489-338818")
    check("different displays get different keys",
          BrightnessController.defaultsKey(for: "a") != BrightnessController.defaultsKey(for: "b"))
}

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
