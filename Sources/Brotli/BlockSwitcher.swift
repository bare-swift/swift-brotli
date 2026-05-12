// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// RFC 7932 § 6 per-alphabet block-switching state.
///
/// One instance per alphabet (L, I, D) per meta-block. Tracks the
/// current block type and the remaining block length; when the block
/// length runs out, reads the next (type, length) pair from the stream.
///
/// **Stage B handoff.** Scaffold in place; the read/advance bodies fill
/// in during Stage B once `PrefixCode.readSymbol` is implemented.
struct BlockSwitcher {
    /// Number of distinct block types for this alphabet (NBLTYPES{L,I,D}).
    /// When `nblTypes == 1`, block switching is disabled and the single
    /// block lasts the entire meta-block.
    let nblTypes: Int

    /// Prefix code over the block-type alphabet (size `nblTypes + 2`).
    /// `nil` when `nblTypes == 1`.
    private var typeCode: PrefixCode?

    /// Prefix code over the 26-symbol block-length alphabet (§ 6 Table 5).
    /// `nil` when `nblTypes == 1`.
    private var lengthCode: PrefixCode?

    /// Current active block type (0..nblTypes-1).
    private(set) var currentType: Int

    /// Number of symbols left in the current block. `Int.max` when block
    /// switching is disabled.
    private(set) var remainingLength: Int

    /// Two-element ring buffer of (previous, second-previous) block types,
    /// referenced by block-type code values 0 and 1 per § 6.
    private var prevType: Int
    private var prevPrevType: Int

    /// Read the NBLTYPES{L,I,D} encoding from the bit stream per § 9.2,
    /// plus the type/length prefix codes and the initial block length.
    /// **Stage B:** implement.
    static func read(_ r: inout BitReader) throws(BrotliError) -> BlockSwitcher {
        // § 9.2 NBLTYPES encoding:
        //   first bit:
        //     0 → NBLTYPES = 1 (no further reads, block switching disabled)
        //     1 → read 3 more bits to select a base + extra-bit count, then
        //         readBits(extraBits). See § 9.2 Table 9.
        // If NBLTYPES > 1:
        //   typeCode = PrefixCode.read(r, alphabetSize: NBLTYPES + 2)
        //   lengthCode = PrefixCode.read(r, alphabetSize: 26)
        //   initial symbol = lengthCode.readSymbol(r) → (base, extraBits) per § 6 Table 5
        //   initial remaining = base + readBits(extraBits)
        fatalError("BlockSwitcher.read — implement in Stage B per RFC 7932 § 6 + § 9.2")
    }

    /// Consume one symbol's worth of block-budget; switch type+length when
    /// the current block runs out. **Stage B:** implement.
    mutating func advance(_ r: inout BitReader) throws(BrotliError) {
        remainingLength -= 1
        if remainingLength > 0 || nblTypes == 1 {
            return
        }
        // Read next type code:
        //   value 0 → currentType = prevPrevType (second-previous)
        //   value 1 → currentType = prevType (previous)
        //   value k ≥ 2 → currentType = k - 2 (direct type index 0..NBLTYPES-1)
        // Update the (prevType, prevPrevType) ring accordingly.
        // Read next length code via lengthCode + extra bits.
        fatalError("BlockSwitcher.advance — implement in Stage B per RFC 7932 § 6")
    }

    /// § 6 Table 5: block-length code base + extra bits.
    static let lengthBase: [Int]  = [1, 5, 9, 13, 17, 25, 33, 41, 49, 65, 81, 97, 113, 145, 177, 209, 241, 305, 369, 497, 753, 1265, 2289, 4337, 8433, 16625]
    static let lengthExtra: [Int] = [2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 7, 8, 9, 10, 11, 12, 13, 24]
}
