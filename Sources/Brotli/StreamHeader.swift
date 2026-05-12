// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// RFC 7932 § 9.1 stream-header reader.
///
/// The first ≤ 7 bits of a brotli stream encode `WBITS`, the base-2 log
/// of the sliding-window size. Valid range: 10..24. Window size in
/// bytes = `(1 << WBITS) - 16` per § 9.1.
enum StreamHeader {
    /// Read the `WBITS` prefix from the bit stream and return the
    /// `WBITS` value (10..24). Throws `.invalidHeader` on the reserved
    /// encoding (first bit 1 followed by six zero bits).
    static func readWBITS(_ r: inout BitReader) throws(BrotliError) -> Int {
        let first = try r.readBit()
        if first == 0 {
            return 16
        }
        // first == 1; read next 3 bits.
        let next3 = try r.readBits(3)
        if next3 != 0 {
            return 17 + Int(next3)
        }
        // first 1, then 000; read final 3 bits.
        let later3 = try r.readBits(3)
        if later3 == 0 {
            throw .invalidHeader
        }
        return 8 + Int(later3)
    }
}
