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

    // The whole point of the change: zero means a black screen, not a dim one.
    check("0% reaches full black",
          abs(GammaDimmer.scale(forPercent: 0)) < 0.0001)

    let curve = stride(from: 0.0, through: 100.0, by: 5).map(GammaDimmer.scale(forPercent:))
    check("scale increases monotonically", curve == curve.sorted())

    check("out-of-range input is clamped",
          [-50.0, -1.0, 101.0, 500.0].allSatisfy {
              let s = GammaDimmer.scale(forPercent: $0)
              return s >= 0 && s <= 1.0
          })
}

suite("DDC gamma ramp") {
    // In DDC mode gamma only acts below the crossover; above it the backlight
    // is doing the work and touching gamma would wash out the picture.
    check("gamma is untouched at the crossover",
          abs(GammaDimmer.rampScale(forPercent: GammaDimmer.crossoverPercent) - 1.0) < 0.0001)
    check("gamma is untouched above the crossover",
          [25.0, 50.0, 100.0].allSatisfy {
              abs(GammaDimmer.rampScale(forPercent: $0) - 1.0) < 0.0001
          })
    check("0% reaches full black",
          abs(GammaDimmer.rampScale(forPercent: 0)) < 0.0001)

    let ramp = stride(from: 0.0, through: 100.0, by: 2.5).map(GammaDimmer.rampScale(forPercent:))
    check("ramp increases monotonically", ramp == ramp.sorted())

    // A step at the crossover would show up as a visible jump mid-slider.
    let below = GammaDimmer.rampScale(forPercent: GammaDimmer.crossoverPercent - 0.01)
    check("ramp is continuous at the crossover", abs(below - 1.0) < 0.01)
}

suite("DDC luminance scaling") {
    // Panels report their own full-scale value; writing the percentage straight
    // through would cap a 0...255 display at roughly 39% of its range.
    check("100% reaches the reported maximum",
          BrightnessController.luminance(forPercent: 100, maximum: 255) == 255)
    check("0% reaches zero",
          BrightnessController.luminance(forPercent: 0, maximum: 255) == 0)
    check("50% lands mid-range",
          BrightnessController.luminance(forPercent: 50, maximum: 255) == 128)
    check("a 0...100 panel is unchanged",
          BrightnessController.luminance(forPercent: 73, maximum: 100) == 73)

    // A display that reports a maximum of zero is malformed; falling back keeps
    // the slider working instead of pinning everything to black.
    check("a zero maximum falls back to 100",
          BrightnessController.luminance(forPercent: 100, maximum: 0) == 100)

    let values = stride(from: 0.0, through: 100.0, by: 5)
        .map { BrightnessController.luminance(forPercent: $0, maximum: 255) }
    check("luminance increases monotonically", values == values.sorted())

    check("out-of-range input is clamped",
          BrightnessController.luminance(forPercent: 500, maximum: 255) == 255
          && BrightnessController.luminance(forPercent: -50, maximum: 255) == 0)
}

suite("Preset levels") {
    // The popover's preset buttons. Kept in sync by hand with
    // BrightnessPopover.presets, which lives in the app target and so is not
    // visible from here.
    let presets: [Double] = [0, 25, 50, 75, 100]

    // Software mode: every preset lands somewhere distinct, 0 is black, 100 is
    // untouched. A preset that collided with another would be a dead button.
    let scales = presets.map(GammaDimmer.scale(forPercent:))
    check("presets are distinct in software mode", Set(scales).count == presets.count)
    check("presets ascend in software mode", scales == scales.sorted())
    check("the 0% preset is black", abs(scales[0]) < 0.0001)
    check("the 100% preset is untouched", abs(scales[4] - 1.0) < 0.0001)

    // DDC mode: every preset except 0 sits above the gamma crossover, so gamma
    // stays out of the way and the backlight alone distinguishes them.
    check("only the 0% preset engages the gamma ramp",
          presets.dropFirst().allSatisfy {
              abs(GammaDimmer.rampScale(forPercent: $0) - 1.0) < 0.0001
          })
    let luminances = presets.map { BrightnessController.luminance(forPercent: $0, maximum: 255) }
    check("presets are distinct in DDC mode", Set(luminances).count == presets.count)
    check("presets ascend in DDC mode", luminances == luminances.sorted())

    // 75% is the newest preset and the one most likely to be mis-specified:
    // it has to sit strictly between 50 and 100 in both modes.
    check("75% sits between 50% and 100% in software mode",
          scales[2] < scales[3] && scales[3] < scales[4])
    check("75% sits between 50% and 100% in DDC mode",
          luminances[2] < luminances[3] && luminances[3] < luminances[4])
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
