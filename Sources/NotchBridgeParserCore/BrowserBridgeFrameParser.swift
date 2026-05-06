import Foundation

// MARK: - Parsed Frame

/// A single decoded WebSocket frame from the receive buffer.
public struct ParsedFrame {
    public let opcode: UInt8
    public let payload: Data
    public let fin: Bool
}

// MARK: - Drained Message

/// A fully-assembled WebSocket message (after fragmentation is resolved).
public enum DrainedMessage {
    /// A complete text or binary message payload.
    case text(Data)
    /// A ping frame; the associated data should be echoed back as a pong.
    case ping(Data)
    /// A close frame was received.
    case close
}

// MARK: - Frame Parser

/// Stateful WebSocket frame parser.
///
/// Feed raw TCP bytes into `receiveBuffer`, then call `drainMessages()` to
/// extract all complete messages.  Thread-safety is the caller's
/// responsibility (``FocusBrowserBridgeServer`` serialises calls on
/// `commandQueue`).
public struct BrowserBridgeFrameParser {

    /// Accumulated receive bytes, not yet parsed into frames.
    public var receiveBuffer = Data()

    /// Bytes collected across continuation frames.
    public private(set) var fragmentBuffer = Data()

    /// Opcode of the first frame in a fragmented message (0x01 or 0x02).
    public private(set) var fragmentOpcode: UInt8 = 0

    /// Maximum allowed payload size per frame (default 2 MB).
    public let maxPayloadBytes: Int

    public init(maxPayloadBytes: Int = 2 * 1024 * 1024) {
        self.maxPayloadBytes = maxPayloadBytes
    }

    // MARK: - Public API

    /// Parse and remove as many complete frames as possible from `receiveBuffer`.
    /// Returns all fully-assembled messages in order.
    public mutating func drainMessages() -> [DrainedMessage] {
        var messages: [DrainedMessage] = []

        while let (consumed, frame) = parseOneFrame(from: receiveBuffer) {
            // Safe removal — guard against a corrupt consumed count.
            if consumed <= receiveBuffer.count {
                receiveBuffer.removeFirst(consumed)
            } else {
                receiveBuffer.removeAll()
            }

            if let msg = assembleFrame(frame) {
                messages.append(msg)
            }
        }

        return messages
    }

    // MARK: - Internal: frame parsing

    /// Parse a single WebSocket frame from the front of `data`.
    ///
    /// Returns `(bytesConsumed, frame)` on success, or `nil` if `data` does
    /// not yet contain a complete frame.  Returns `nil` (not a crash) if the
    /// payload exceeds `maxPayloadBytes` or the extended-length encoding is
    /// malformed.
    public func parseOneFrame(from data: Data) -> (Int, ParsedFrame)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }

        let firstByte = bytes[0]
        let fin = (firstByte & 0x80) != 0
        let opcode = firstByte & 0x0F

        let masked = (bytes[1] & 0x80) != 0
        var length = Int(bytes[1] & 0x7F)
        var offset = 2

        switch length {
        case 126:
            guard bytes.count >= offset + 2 else { return nil }
            length = (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
            offset += 2
        case 127:
            guard bytes.count >= offset + 8 else { return nil }
            var len: UInt64 = 0
            for i in 0..<8 {
                len = (len << 8) | UInt64(bytes[offset + i])
            }
            // Guard against UInt64 → Int overflow and absurd sizes.
            guard len <= UInt64(maxPayloadBytes) else { return nil }
            length = Int(len)
            offset += 8
        default:
            break
        }

        guard length <= maxPayloadBytes else { return nil }

        var mask: [UInt8] = []
        if masked {
            guard bytes.count >= offset + 4 else { return nil }
            mask = Array(bytes[offset..<offset + 4])
            offset += 4
        }

        let totalFrameSize = offset + length
        guard bytes.count >= totalFrameSize else { return nil }

        var payloadBytes = Array(bytes[offset..<totalFrameSize])
        if masked {
            for i in 0..<payloadBytes.count {
                payloadBytes[i] ^= mask[i % 4]
            }
        }

        return (totalFrameSize, ParsedFrame(opcode: opcode, payload: Data(payloadBytes), fin: fin))
    }

    // MARK: - Internal: message assembly

    /// Handle fragmentation and return a `DrainedMessage` when a full message
    /// is assembled, or `nil` for intermediate continuation frames.
    private mutating func assembleFrame(_ frame: ParsedFrame) -> DrainedMessage? {
        switch frame.opcode {
        case 0x00: // Continuation
            fragmentBuffer.append(frame.payload)
            if frame.fin {
                let full = fragmentBuffer
                let opcode = fragmentOpcode
                fragmentBuffer = Data()
                fragmentOpcode = 0
                return opcodeToMessage(opcode: opcode, payload: full)
            }
            return nil

        case 0x01, 0x02: // Text / Binary
            if frame.fin {
                return opcodeToMessage(opcode: frame.opcode, payload: frame.payload)
            }
            // Start of a fragmented message.
            fragmentOpcode = frame.opcode
            fragmentBuffer = frame.payload
            return nil

        case 0x08: // Close
            return .close

        case 0x09: // Ping
            return .ping(frame.payload)

        default:
            return nil
        }
    }

    private func opcodeToMessage(opcode: UInt8, payload: Data) -> DrainedMessage? {
        // Both text (0x01) and binary (0x02) are surfaced as `.text` since
        // the bridge only uses UTF-8 JSON.
        switch opcode {
        case 0x01, 0x02: return .text(payload)
        default: return nil
        }
    }
}
