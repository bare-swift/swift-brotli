// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// RFC 7932 § 6 per-alphabet block-switching state.
///
/// One instance per alphabet (L, I, D) per meta-block. Tracks the
/// current block type and the remaining block length; when the block
/// length runs out, reads the next (type, length) pair from the stream.
struct BlockSwitcher {
    /// Number of distinct block types for this alphabet
    /// (NBLTYPESL / NBLTYPESI / NBLTYPESD).
    let nblTypes: Int

    /// Prefix code over the block-type alphabet (size `nblTypes + 2`).
    /// `nil` when `nblTypes == 1`.
    private var typeCode: PrefixCode?

    /// Prefix code over the 26-symbol block-length alphabet.
    /// `nil` when `nblTypes == 1`.
    private var lengthCode: PrefixCode?

    /// Current active block type (0..nblTypes-1). Initialized to 0 per § 6.
    private(set) var currentType: Int = 0

    /// Number of symbols left in the current block. `Int.max` when block
    /// switching is disabled.
    private(set) var remainingLength: Int

    /// "Previous block type" per § 6. Initialized to 1 (so that a
    /// type-symbol-0 immediately after the meta-block header switches
    /// to type 1).
    private var prevType: Int = 1

    private init(nblTypes: Int,
                 typeCode: PrefixCode?,
                 lengthCode: PrefixCode?,
                 initialLength: Int) {
        self.nblTypes = nblTypes
        self.typeCode = typeCode
        self.lengthCode = lengthCode
        self.remainingLength = initialLength
    }

    /// Read NBLTYPES + optional prefix codes + initial block length from
    /// the meta-block header per § 9.2 + § 6.
    static func read(_ r: inout BitReader) throws(BrotliError) -> BlockSwitcher {
        let nblTypes = try readVariableLengthCount(&r)
        if nblTypes == 1 {
            return BlockSwitcher(nblTypes: 1, typeCode: nil, lengthCode: nil, initialLength: Int.max)
        }
        let typeCode = try PrefixCode.read(&r, alphabetSize: nblTypes + 2)
        let lengthCode = try PrefixCode.read(&r, alphabetSize: 26)
        var lengthCode2 = lengthCode
        let initial = try readBlockLength(&r, code: &lengthCode2)
        return BlockSwitcher(nblTypes: nblTypes,
                             typeCode: typeCode,
                             lengthCode: lengthCode2,
                             initialLength: initial)
    }

    /// Consume one symbol's worth of block-budget; switch type+length when
    /// the current block runs out.
    mutating func advance(_ r: inout BitReader) throws(BrotliError) {
        remainingLength -= 1
        if remainingLength > 0 || nblTypes == 1 { return }
        // Read next (type, length).
        guard let tCode = typeCode, var lCode = lengthCode else {
            // Should not happen given nblTypes > 1.
            throw BrotliError.invalidBlockType
        }
        let typeSym = try tCode.readSymbol(&r)
        let saved = currentType
        switch typeSym {
        case 0:
            // Switch to "the type that preceded the current type".
            currentType = prevType
        case 1:
            // Switch to current_type + 1 mod NBLTYPES.
            currentType = (currentType + 1) % nblTypes
        default:
            // Direct: typeSym - 2.
            let direct = typeSym - 2
            guard direct >= 0 && direct < nblTypes else {
                throw BrotliError.invalidBlockType
            }
            currentType = direct
        }
        prevType = saved
        remainingLength = try BlockSwitcher.readBlockLength(&r, code: &lCode)
        lengthCode = lCode
    }

    /// § 9.2 NBLTYPES-style variable-length count encoding. Also used for
    /// NTREESL / NTREESD.
    static func readVariableLengthCount(_ r: inout BitReader) throws(BrotliError) -> Int {
        let lead = try r.readBit()
        if lead == 0 { return 1 }
        let marker = Int(try r.readBits(3))
        if marker == 0 { return 2 }
        let extras = Int(try r.readBits(marker))
        let base = (1 << marker) + 1
        return base + extras
    }

    /// § 6 block-length: read a length-code symbol, then `extraBits[code]`
    /// extra bits; return `base[code] + extras`.
    static func readBlockLength(_ r: inout BitReader, code: inout PrefixCode) throws(BrotliError) -> Int {
        let sym = try code.readSymbol(&r)
        guard sym >= 0 && sym < 26 else { throw BrotliError.invalidPrefixCode }
        let base = lengthBase[sym]
        let extra = lengthExtra[sym]
        let extraValue = extra == 0 ? 0 : Int(try r.readBits(extra))
        return base + extraValue
    }

    /// § 6 Table 5: block-length code base + extra bits (26 codes).
    static let lengthBase: [Int]  = [1, 5, 9, 13, 17, 25, 33, 41, 49, 65, 81, 97, 113, 145, 177, 209, 241, 305, 369, 497, 753, 1265, 2289, 4337, 8433, 16625]
    static let lengthExtra: [Int] = [2, 2, 2,  2,  3,  3,  3,  3,  4,  4,  4,  4,   5,   5,   5,   5,   6,   6,   7,   8,   9,    10,    11,    12,    13,    24]
}
