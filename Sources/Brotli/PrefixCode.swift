// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// RFC 7932 § 3 prefix codes (Huffman-like) — simple form (§ 3.1) and
/// complex form (§ 3.2).
///
/// **Stage B handoff.** The scaffold is in place; the algorithm bodies
/// (canonical-code construction, symbol decode, complex-form length
/// decoding with chain-repeat semantics) are filled in during Stage B.
/// Once filled, this type provides a lookup table that maps bit
/// sequences to (symbol, length) for downstream alphabets (literals,
/// insert-and-copy, distance, code-length, block-switch, context-map).
struct PrefixCode {
    /// RFC 7932 caps normal alphabet code lengths at 15.
    static let maxNormalBits = 15
    /// Code-length code (§ 3.5) caps at 5 bits.
    static let maxCodeLengthBits = 5

    /// Symbol → code length array, parallel to alphabet indices.
    /// Length 0 means "symbol absent from this code".
    let lengths: [Int]

    /// Canonical code for each symbol (MSB-first), parallel to `lengths`.
    /// Entry value is meaningless when `lengths[i] == 0`.
    let codes: [UInt32]

    /// Maximum code length seen in this code (0 if alphabet has no symbols).
    let maxBitsInUse: Int

    /// Read a prefix-code declaration from the bit stream per RFC 7932 § 3.
    static func read(
        _ r: inout BitReader,
        alphabetSize: Int,
        maxBits: Int = PrefixCode.maxNormalBits
    ) throws(BrotliError) -> PrefixCode {
        // First 2 bits: 01 → simple form (§ 3.1); else complex form with
        // HSKIP = value of those 2 bits (§ 3.4).
        let selector = try r.readBits(2)
        if selector == 1 {
            return try readSimple(&r, alphabetSize: alphabetSize, maxBits: maxBits)
        }
        return try readComplex(&r, hskip: Int(selector), alphabetSize: alphabetSize, maxBits: maxBits)
    }

    /// Decode one symbol from the bit stream using this prefix code.
    /// **Stage B:** replace `fatalError` with the lookup. Recommended
    /// implementation: incrementally read bits, accumulate MSB-first
    /// candidate, check against canonical codes by length. Or build a
    /// flat 2^maxBitsInUse lookup table at construction time for O(1)
    /// decode at the cost of upfront memory.
    mutating func readSymbol(_ r: inout BitReader) throws(BrotliError) -> Int {
        // Stage B: implement per RFC 7932 § 3.4 decoding procedure.
        fatalError("PrefixCode.readSymbol — implement in Stage B per RFC 7932 § 3.4")
    }

    private static func readSimple(
        _ r: inout BitReader,
        alphabetSize: Int,
        maxBits: Int
    ) throws(BrotliError) -> PrefixCode {
        // Stage B: implement per RFC 7932 § 3.1.
        //   NSYM = readBits(2) + 1, range 1..4
        //   bits-per-symbol = ceil(log2(alphabetSize))
        //   Read NSYM symbol values, each `bits-per-symbol` bits.
        //   Sort symbol values ascending.
        //   Assign code lengths per § 3.1 NSYM table:
        //     NSYM=1 → [0]                      (one symbol, zero-bit code)
        //     NSYM=2 → [1, 1]
        //     NSYM=3 → [1, 2, 2]
        //     NSYM=4 → readBits(1) "tree-select":
        //                0 → [2, 2, 2, 2]
        //                1 → [1, 2, 3, 3]
        fatalError("PrefixCode.readSimple — implement in Stage B per RFC 7932 § 3.1")
    }

    private static func readComplex(
        _ r: inout BitReader,
        hskip: Int,
        alphabetSize: Int,
        maxBits: Int
    ) throws(BrotliError) -> PrefixCode {
        // Stage B: implement per RFC 7932 § 3.2 + § 3.4 + § 3.5.
        //
        //   Code-length-code order (§ 3.5):
        //     [1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15]
        //
        //   The first `hskip` entries of the code-length-code lengths are
        //   forced to 0. The rest are read as 2-bit values from the bit
        //   stream until the running sum of "non-zero-length count" reaches 32
        //   (i.e. the prefix code over the code-length alphabet is complete).
        //
        //   Then use the code-length-code (small Huffman, maxBits=5) to
        //   decode the actual alphabet's code lengths. Symbols 0..15 emit
        //   that length. Symbol 16 is "repeat the last non-zero length";
        //   symbol 17 is "repeat zero". Both have chained-repeat semantics
        //   (see § 3.4).
        //
        //   Read until total symbols emitted == alphabetSize. Then build
        //   the canonical codes (same procedure as DEFLATE; see
        //   swift-deflate's HuffmanEncoder.canonicalCodes for the
        //   reference shape).
        fatalError("PrefixCode.readComplex — implement in Stage B per RFC 7932 § 3.2 + 3.4 + 3.5")
    }

    /// Code-length-code symbol ordering per RFC 7932 § 3.5.
    static let codeLengthOrder: [Int] = [
        1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    ]
}
