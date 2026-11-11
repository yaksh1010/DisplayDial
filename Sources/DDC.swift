import Foundation
import IOKit

/// VESA MCCS control codes DisplayDial knows how to show.
enum VCP: UInt8, CaseIterable {
    case factoryReset = 0x04
    case brightness = 0x10
    case contrast = 0x12
    case colorPreset = 0x14
    case redGain = 0x16, greenGain = 0x18, blueGain = 0x1A
    case redSaturation = 0x59, yellowSaturation = 0x5A, greenSaturation = 0x5B
    case cyanSaturation = 0x5C, blueSaturation = 0x5D, magentaSaturation = 0x5E
    case redBlackLevel = 0x6C, greenBlackLevel = 0x6E, blueBlackLevel = 0x70
    case sharpness = 0x87

    /// Read first so the main sliders fill in quickly.
    static let essentials: [VCP] = [.brightness, .contrast, .colorPreset]
}

/// What the monitor says it supports: code → allowed values (empty means any value up to its maximum).
struct Capabilities {
    var codes: [UInt8: [UInt8]] = [:]

    /// Parses the `vcp(...)` part of a capabilities string such as `vcp(10 12 14(05 08 0B) 16)`.
    init?(_ text: String) {
        guard let start = text.range(of: "vcp(") else { return nil }
        var depth = 1
        var token = ""
        var current: UInt8?

        func finishToken() {
            guard let value = UInt8(token, radix: 16) else {
                token = ""
                return
            }
            if depth == 1 {
                current = value
                codes[value] = codes[value] ?? []
            } else if depth == 2, let current {
                codes[current, default: []].append(value)
            }
            token = ""
        }

        for character in text[start.upperBound...] {
            switch character {
            case "(":
                finishToken()
                depth += 1
            case ")":
                finishToken()
                depth -= 1
                if depth == 0 { return }
            case " ":
                finishToken()
            default:
                if character.isHexDigit { token.append(character) }
            }
        }
        if codes.isEmpty { return nil }
    }
}

/// One monitor's DDC/CI line. All I/O runs on a private serial queue because each command
/// needs a pause before the monitor answers.
final class DDCChannel {
    private let service: CFTypeRef
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pending: [UInt8: UInt16] = [:]
    private var flushScheduled = false

    init(service: CFTypeRef, label: String) {
        self.service = service
        queue = DispatchQueue(label: "dev.displaydial.ddc.\(label)", qos: .userInitiated)
    }

    /// Runs `work` on the DDC queue, after any writes already queued.
    func perform(_ work: @escaping (DDCChannel) -> Void) {
        queue.async { work(self) }
    }

    /// Queues a value. Slider drags send many values; only the newest per code is written.
    func set(_ code: UInt8, _ value: Int) {
        lock.lock()
        pending[code] = UInt16(clamping: value)
        let schedule = !flushScheduled
        flushScheduled = true
        lock.unlock()
        if schedule {
            queue.asyncAfter(deadline: .now() + 0.03) { self.flush() }
        }
    }

    private func flush() {
        lock.lock()
        let items = pending
        pending = [:]
        flushScheduled = false
        lock.unlock()
        for (code, value) in items {
            write([0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)])
            usleep(20_000)
        }
    }

    // MARK: Blocking calls — only use inside `perform`.

    func read(_ code: UInt8) -> (value: Int, maximum: Int)? {
        for _ in 0..<4 {
            write([0x82, 0x01, code])
            usleep(50_000)
            if let reply = receive(12), reply[2] == 0x02, reply[4] == code {
                guard reply[3] == 0 else { return nil }  // monitor says: unsupported
                let maximum = Int(reply[6]) << 8 | Int(reply[7])
                let value = Int(reply[8]) << 8 | Int(reply[9])
                return (value, maximum)
            }
            usleep(30_000)
        }
        return nil
    }

    func capabilities() -> String? {
        var bytes: [UInt8] = []
        var offset = 0
        while offset < 2048 {
            var chunk: [UInt8]?
            for _ in 0..<5 {
                write([0x83, 0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF)])
                usleep(60_000)
                if let reply = receive(38), reply[2] == 0xE3, Int(reply[3]) << 8 | Int(reply[4]) == offset {
                    let length = Int(reply[1] & 0x7F) - 3
                    chunk = length > 0 ? Array(reply[5..<min(5 + length, 37)]) : []
                    break
                }
            }
            guard let chunk, !chunk.isEmpty else { break }
            bytes += chunk.filter { $0 != 0 }
            offset += chunk.count
        }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }

    private func write(_ bytes: [UInt8]) {
        var packet = bytes
        var checksum: UInt8 = 0x6E ^ 0x51
        for byte in packet { checksum ^= byte }
        packet.append(checksum)
        _ = packet.withUnsafeMutableBytes {
            IOAVServiceWriteI2C(service, 0x37, 0x51, $0.baseAddress, UInt32($0.count))
        }
    }

    private func receive(_ count: Int) -> [UInt8]? {
        var reply = [UInt8](repeating: 0, count: count)
        let status = reply.withUnsafeMutableBytes {
            IOAVServiceReadI2C(service, 0x37, 0x51, $0.baseAddress, UInt32(count))
        }
        return status == kIOReturnSuccess ? reply : nil
    }

    /// DDC services for external displays, in IORegistry order (Apple Silicon only).
    static func externalServices() -> [CFTypeRef] {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"),
                                           &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var services: [CFTypeRef] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            let location = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            if location == "External", let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry) {
                services.append(service)
            }
        }
        return services
    }
}
