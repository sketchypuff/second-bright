import Foundation
import IOKit

/// DDC/CI over I2C on Apple Silicon.
///
/// There is no public API for this. Every tool that adjusts an external monitor's
/// backlight on an M-series Mac goes through the same three private symbols, which
/// we resolve at runtime rather than link against: if a future macOS drops them the
/// app falls back to software dimming instead of failing to launch.
///
/// `@unchecked Sendable`: the mutable pacing state is only ever touched from the
/// single serial queue `BrightnessController` confines this object to. DDC is a
/// stateful, order-sensitive protocol, so concurrent use would corrupt it anyway.
public final class DDCService: @unchecked Sendable {

    // MARK: - Private symbol resolution

    private typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias WriteI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    private typealias ReadI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private struct Symbols {
        let create: CreateWithService
        let write: WriteI2C
        let read: ReadI2C
    }

    private static let symbols: Symbols? = {
        // These live in IOKit today; CoreDisplay is checked as a fallback in case
        // they move. RTLD_DEFAULT first, since IOKit is already linked into us.
        let handles: [UnsafeMutableRawPointer?] = [
            UnsafeMutableRawPointer(bitPattern: -2), // RTLD_DEFAULT
            dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
            dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY),
        ]
        for handle in handles {
            guard let create = dlsym(handle, "IOAVServiceCreateWithService"),
                  let write = dlsym(handle, "IOAVServiceWriteI2C"),
                  let read = dlsym(handle, "IOAVServiceReadI2C")
            else { continue }
            return Symbols(
                create: unsafeBitCast(create, to: CreateWithService.self),
                write: unsafeBitCast(write, to: WriteI2C.self),
                read: unsafeBitCast(read, to: ReadI2C.self)
            )
        }
        return nil
    }()

    public static var isSupported: Bool { symbols != nil }

    // MARK: - DDC/CI wire constants

    /// I2C address of the DDC/CI slave on every compliant display.
    private static let chipAddress: UInt32 = 0x37
    /// Offset the host writes at / reads from.
    private static let dataAddress: UInt32 = 0x51
    /// Checksum seed: destination address ^ source address.
    private static let checksumSeed: UInt8 = 0x6E ^ 0x51

    /// VCP feature codes.
    public enum VCP: UInt8 {
        case luminance = 0x10
    }

    /// The DDC/CI spec requires a gap between transactions; going faster makes
    /// displays drop commands or return garbage.
    private static let writeInterval: TimeInterval = 0.05
    private static let readDelay: UInt32 = 40_000 // microseconds

    // MARK: - Lifecycle

    private let avService: CFTypeRef
    private var lastWrite = Date.distantPast

    private init(avService: CFTypeRef) {
        self.avService = avService
    }

    /// Opens the AV service for the external display, or nil if there isn't one.
    ///
    /// Selection is by `Location == "External"`, which is what distinguishes the
    /// plugged-in monitor from the built-in panel.
    public static func forExternalDisplay() -> DDCService? {
        guard let symbols else { return nil }
        for service in externalAVServiceProxies() {
            defer { IOObjectRelease(service) }
            if let ref = symbols.create(kCFAllocatorDefault, service)?.takeRetainedValue() {
                return DDCService(avService: ref)
            }
        }
        return nil
    }

    /// The `DCPAVServiceProxy` IOKit nodes belonging to non-built-in displays.
    public static func externalAVServiceProxies() -> [io_service_t] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"), &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var result: [io_service_t] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            let location = IORegistryEntryCreateCFProperty(
                service, "Location" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? String
            if location == "External" {
                result.append(service)
            } else {
                IOObjectRelease(service)
            }
        }
        return result
    }

    // MARK: - Transactions

    private func pace() {
        let elapsed = Date().timeIntervalSince(lastWrite)
        if elapsed < Self.writeInterval {
            Thread.sleep(forTimeInterval: Self.writeInterval - elapsed)
        }
        lastWrite = Date()
    }

    /// Set VCP Feature.
    @discardableResult
    public func write(_ vcp: VCP, value: UInt16) -> Bool {
        guard let symbols = Self.symbols else { return false }
        var packet: [UInt8] = [
            0x84,                    // 0x80 | payload length (4)
            0x03,                    // Set VCP Feature
            vcp.rawValue,
            UInt8(value >> 8),
            UInt8(value & 0xFF),
            0,
        ]
        packet[5] = packet[0..<5].reduce(Self.checksumSeed, ^)

        pace()
        return packet.withUnsafeMutableBytes { buffer in
            symbols.write(avService, Self.chipAddress, Self.dataAddress,
                          buffer.baseAddress!, UInt32(buffer.count)) == kIOReturnSuccess
        }
    }

    public struct Reading {
        public let current: UInt16
        public let maximum: UInt16
        public let raw: [UInt8]
    }

    /// Get VCP Feature. Returns nil when the display doesn't answer or answers with junk.
    public func read(_ vcp: VCP) -> Reading? {
        guard let symbols = Self.symbols else { return nil }
        var request: [UInt8] = [0x82, 0x01, vcp.rawValue, 0]
        request[3] = request[0..<3].reduce(Self.checksumSeed, ^)

        pace()
        let wrote = request.withUnsafeMutableBytes { buffer in
            symbols.write(avService, Self.chipAddress, Self.dataAddress,
                          buffer.baseAddress!, UInt32(buffer.count)) == kIOReturnSuccess
        }
        guard wrote else { return nil }

        usleep(Self.readDelay)

        var reply = [UInt8](repeating: 0, count: 12)
        let didRead = reply.withUnsafeMutableBytes { buffer in
            symbols.read(avService, Self.chipAddress, Self.dataAddress,
                         buffer.baseAddress!, UInt32(buffer.count)) == kIOReturnSuccess
        }
        guard didRead else { return nil }
        lastWrite = Date()

        guard let parsed = Self.parseReply(reply, vcp: vcp) else { return nil }
        return Reading(current: parsed.current, maximum: parsed.maximum, raw: reply)
    }

    /// Reads the first bytes of the display's EDID (I2C address 0x50).
    ///
    /// This separates "the I2C channel is broken" from "the channel works but the
    /// panel refuses DDC/CI": the EDID EEPROM answers on every working link, so a
    /// good EDID read alongside a failing 0x37 read localises the fault to the
    /// monitor rather than the cable or the Mac.
    public func readEDIDHeader() -> [UInt8]? {
        guard let symbols = Self.symbols else { return nil }
        var buffer = [UInt8](repeating: 0, count: 16)
        let ok = buffer.withUnsafeMutableBytes { b in
            symbols.read(avService, 0x50, 0x00, b.baseAddress!, UInt32(b.count)) == kIOReturnSuccess
        }
        guard ok, buffer.prefix(8) == [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00] else {
            return nil
        }
        return buffer
    }

    /// Locates the Get VCP Feature Reply inside a raw I2C read.
    ///
    /// The reply frame is scanned for rather than read at a fixed offset: how many
    /// leading address bytes the read includes varies, and anchoring on the opcode
    /// makes this correct either way.
    public static func parseReply(_ reply: [UInt8], vcp: VCP) -> (current: UInt16, maximum: UInt16)? {
        for i in 0..<reply.count where reply[i] == 0x02 {
            // opcode, result code (0 == ok), the feature we asked about,
            // type, max hi/lo, current hi/lo
            guard i + 7 < reply.count,
                  reply[i + 1] == 0x00,
                  reply[i + 2] == vcp.rawValue
            else { continue }
            let maximum = UInt16(reply[i + 4]) << 8 | UInt16(reply[i + 5])
            let current = UInt16(reply[i + 6]) << 8 | UInt16(reply[i + 7])
            guard maximum > 0, current <= maximum else { continue }
            return (current, maximum)
        }
        return nil
    }
}
