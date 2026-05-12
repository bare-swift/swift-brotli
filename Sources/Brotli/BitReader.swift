// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes

/// LSB-first bit reader per RFC 7932 § 1.4.
///
/// Bits within a byte are emitted least-significant first; multi-bit
/// values pack the lower-order bits before higher-order. Bytes are
/// consumed in stream order. Matches DEFLATE's bit ordering, so the
/// implementation mirrors swift-deflate's `BitReader`.
struct BitReader {
    let bytes: ContiguousArray<UInt8>
    private var bytePos: Int = 0
    private(set) var bitsInBuffer: Int = 0
    private var buffer: UInt64 = 0

    init(_ source: Bytes) {
        self.bytes = source.storage
    }

    /// Read `count` bits (`count <= 32`) as an unsigned integer.
    @inlinable
    mutating func readBits(_ count: Int) throws(BrotliError) -> UInt32 {
        precondition(count >= 0 && count <= 32)
        if count == 0 { return 0 }
        try ensure(bits: count)
        let mask: UInt64 = count == 64 ? UInt64.max : (UInt64(1) << count) - 1
        let value = buffer & mask
        buffer >>= count
        bitsInBuffer -= count
        return UInt32(truncatingIfNeeded: value)
    }

    /// Read a single bit.
    @inlinable
    mutating func readBit() throws(BrotliError) -> UInt32 {
        try readBits(1)
    }

    /// Discard whatever bits remain in the current byte. Used before
    /// reading byte-aligned MSKIPLEN payloads and uncompressed meta-blocks.
    mutating func alignToByte() {
        let drop = bitsInBuffer & 7
        if drop != 0 {
            buffer >>= drop
            bitsInBuffer -= drop
        }
    }

    /// Consume `count` whole bytes from the underlying buffer (only
    /// legal after ``alignToByte()``).
    mutating func readBytes(_ count: Int) throws(BrotliError) -> ContiguousArray<UInt8> {
        var out = ContiguousArray<UInt8>()
        out.reserveCapacity(count)
        var remaining = count
        // Drain any full bytes still sitting in the bit buffer first.
        while bitsInBuffer >= 8 && remaining > 0 {
            out.append(UInt8(truncatingIfNeeded: buffer & 0xFF))
            buffer >>= 8
            bitsInBuffer -= 8
            remaining -= 1
        }
        guard bytePos + remaining <= bytes.count else {
            throw .truncated
        }
        for _ in 0..<remaining {
            out.append(bytes[bytePos])
            bytePos += 1
        }
        return out
    }

    /// Refill the bit buffer until it holds at least `bits` bits.
    private mutating func ensure(bits: Int) throws(BrotliError) {
        while bitsInBuffer < bits {
            guard bytePos < bytes.count else { throw .truncated }
            buffer |= UInt64(bytes[bytePos]) << bitsInBuffer
            bytePos += 1
            bitsInBuffer += 8
        }
    }
}
