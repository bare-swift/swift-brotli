// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes

/// LSB-first bit-level output buffer for brotli streams.
/// RFC 7932 § 1: "The bit ordering within a byte is LSB-first."
///
/// Encoder analog of ``BitReader``.
struct BitWriter {
    private var buffer: UInt64 = 0
    private var bitsInBuffer: Int = 0
    private var bytes: ContiguousArray<UInt8> = []

    /// Append the low `count` bits of `value` to the stream, LSB-first.
    /// Caller MUST ensure `count` is in 0...32 and `value`'s upper
    /// `32 - count` bits are zero. v0.2 callers are internal and meet
    /// both preconditions.
    mutating func writeBits(_ value: UInt32, count: Int) {
        if count == 0 { return }
        buffer |= UInt64(value) << bitsInBuffer
        bitsInBuffer += count
        while bitsInBuffer >= 8 {
            bytes.append(UInt8(buffer & 0xFF))
            buffer >>= 8
            bitsInBuffer -= 8
        }
    }

    /// Convenience for `writeBits(bit, count: 1)`.
    mutating func writeBit(_ bit: UInt32) {
        writeBits(bit & 1, count: 1)
    }

    /// Pad the current byte with zero bits so the next write starts on a
    /// byte boundary.
    mutating func alignToByte() {
        if bitsInBuffer > 0 {
            bytes.append(UInt8(buffer & 0xFF))
            buffer = 0
            bitsInBuffer = 0
        }
    }

    /// Finalize and return the accumulated bytes. Flushes any partial byte.
    func finalize() -> Bytes {
        var copy = self
        copy.alignToByte()
        return Bytes(Array(copy.bytes))
    }

    /// Return the byte-aligned portion of the accumulated bytes and reset
    /// the byte buffer to empty. The partial-byte buffer (`buffer` /
    /// `bitsInBuffer`) is preserved unchanged — subsequent writes continue
    /// at the same bit offset as if drain had not been called.
    ///
    /// Caller of `Brotli.Streaming.Encoder.drain()` uses this to pipe
    /// accumulated bytes out incrementally without terminating the stream.
    mutating func drain() -> Bytes {
        let result = Bytes(Array(bytes))
        bytes.removeAll(keepingCapacity: true)
        return result
    }
}
