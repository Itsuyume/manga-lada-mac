import Foundation
import zlib

/// ImageIO can decode damaged PNGs; cached pages must also pass every chunk CRC.
enum PNGCacheValidation {
    private static let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    static func isComplete(_ data: Data) -> Bool {
        data.withUnsafeBytes { validate($0.bindMemory(to: UInt8.self)) }
    }

    private static func validate(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard bytes.count >= 8, bytes.prefix(8).elementsEqual(signature),
              let base = bytes.baseAddress else { return false }
        var offset = 8
        var hasImageData = false
        while offset <= bytes.count - 12 {
            let length = Int(integer(bytes, at: offset))
            guard length <= Int32.max, length <= bytes.count - offset - 12 else { return false }
            let type = integer(bytes, at: offset + 4)
            let checksum = integer(bytes, at: offset + 8 + length)
            guard crc32(0, base + offset + 4, uInt(length + 4)) == checksum else { return false }
            if offset == 8 && (type != 0x49484452 || length != 13) { return false }
            if type == 0x49444154 { hasImageData = true }
            offset += length + 12
            if type == 0x49454E44 { return length == 0 && hasImageData && offset == bytes.count }
        }
        return false
    }

    private static func integer(_ bytes: UnsafeBufferPointer<UInt8>, at offset: Int) -> UInt32 {
        bytes[offset..<(offset + 4)].reduce(0) { $0 << 8 | UInt32($1) }
    }
}
