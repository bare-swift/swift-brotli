// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// RFC 7932 § 5 insert-and-copy length decoder.
///
/// The insert-and-copy alphabet has 704 symbols. Each symbol decomposes
/// into `(insertLen, copyLen, distanceContext, useDistance)`. The
/// 704-symbol decomposition uses § 5 Table 4: high bits select an
/// (insert-code, copy-code) group, low bits select the variant within.
///
/// Insert codes and copy codes further decompose into (base, extraBits)
/// per § 5 Tables 5 and 6.
enum InsertCopy {
    /// § 5 Table 5: insert-code base values + extra bits (24 codes, 0..23).
    static let insertBase: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 8, 10, 14, 18, 26, 34, 50, 66, 98, 130, 194, 322, 578, 1090, 2114, 6210, 22594,
    ]
    static let insertExtra: [Int] = [
        0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 12, 14, 24,
    ]

    /// § 5 Table 6: copy-code base values + extra bits (24 codes, 0..23).
    static let copyBase: [Int] = [
        2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 18, 22, 30, 38, 54, 70, 102, 134, 198, 326, 582, 1094, 2118,
    ]
    static let copyExtra: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 24,
    ]

    /// Decompose a 0..703 insert-and-copy symbol into (insertCode,
    /// copyCode, useDistance) per § 5 Table 4. Extra bits for both codes
    /// are *not* read here — caller reads them after looking up the
    /// (base, extraBits) from the tables above.
    ///
    /// Symbol layout per § 5 (high → low bits, 0..9 == 10 bits):
    ///   bits 9..6 of symbol-index (well, of the (symbol >> 6) value):
    ///     The 704 symbols partition into 8 groups of 88. Each group is
    ///     identified by `(symbol >> 6) & 0x7`, value 0..7:
    ///       group 0: insertCode group 0, copyCode group 0, useDistance=false
    ///       group 1: insertCode group 0, copyCode group 1, useDistance=false
    ///       group 2: insertCode group 1, copyCode group 0, useDistance=false
    ///       group 3: insertCode group 1, copyCode group 1, useDistance=false
    ///       group 4: insertCode group 2, copyCode group 0, useDistance=true
    ///       group 5: insertCode group 2, copyCode group 1, useDistance=true
    ///       group 6: insertCode group 3, copyCode group 0, useDistance=true
    ///       group 7: insertCode group 3, copyCode group 1, useDistance=true
    ///   bits 5..3 of symbol (3 bits) select within copy-code-group
    ///   bits 2..0 of symbol (3 bits) select within insert-code-group
    ///
    /// Insert-code-group → insert-code base index:
    ///   group 0: insertCode = 0..7 (the 8 low-insert-length codes, extra=0)
    ///   group 1: insertCode = 8..15 (insertCode = 8 + low3 of symbol-low)
    ///   group 2: insertCode = 16..23 with index = 16 + low3
    ///   group 3 (and only group with non-zero distance context): same as group 2
    ///   ↑ But actually § 5 Table 4 maps the group to a *different* set of
    ///     insert-codes; the executor reads the spec text carefully.
    ///
    /// **Stage B:** finish the symbol-to-(insertCode, copyCode) mapping
    /// per § 5 Table 4. The base/extra tables above are correct and
    /// final; only the high-level decomposition stays to be implemented.
    static func decompose(_ symbol: Int) throws(BrotliError) -> (insertCode: Int, copyCode: Int, useDistance: Bool, distContextOffset: Int) {
        guard symbol >= 0 && symbol < 704 else { throw .invalidPrefixCode }
        // Stage B: implement per § 5 Table 4.
        fatalError("InsertCopy.decompose — implement in Stage B per RFC 7932 § 5 Table 4")
    }
}
