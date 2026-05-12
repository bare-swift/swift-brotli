// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// RFC 7932 § 5 insert-and-copy length decoder.
///
/// The insert-and-copy alphabet has 704 symbols. Each symbol decomposes
/// into `(insertCode, copyCode, useDistance)`. § 5's Table 4 maps the
/// 704 symbols to 11 cells of 64 values each; within a cell, the low
/// 3 bits select the copy-code offset and the next 3 bits select the
/// insert-code offset.
///
/// Insert / copy codes further decompose into `(base, extraBits)` per
/// § 5's insert and copy tables (length 24 each); the executor reads
/// extra bits from the stream after the symbol is decoded.
enum InsertCopy {
    /// § 5 insert-length code: base value + extra bits (24 codes, 0..23).
    static let insertBase: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 8, 10, 14, 18, 26, 34, 50, 66, 98, 130, 194, 322, 578, 1090, 2114, 6210, 22594,
    ]
    static let insertExtra: [Int] = [
        0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 12, 14, 24,
    ]

    /// § 5 copy-length code: base value + extra bits (24 codes, 0..23).
    static let copyBase: [Int] = [
        2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 18, 22, 30, 38, 54, 70, 102, 134, 198, 326, 582, 1094, 2118,
    ]
    static let copyExtra: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 24,
    ]

    /// Decompose a 0..703 insert-and-copy symbol into `(insertCode,
    /// copyCode, useDistance)` per § 5 Table 4. **Extra bits are not
    /// read here** — caller reads them based on `insertExtra[insertCode]`
    /// and `copyExtra[copyCode]`.
    ///
    /// `useDistance == false` iff the symbol lies in the top row of
    /// Table 4 (symbols 0..127), in which case the distance is reused
    /// (the last-distance ring buffer's most recent entry).
    static func decompose(_ symbol: Int) throws(BrotliError) -> (insertCode: Int, copyCode: Int, useDistance: Bool) {
        guard symbol >= 0 && symbol < 704 else { throw .invalidPrefixCode }
        // Cell index = symbol >> 6 (0..10).
        let cell = symbol >> 6
        let (insertBaseRange, copyBaseRange, useDist) = Self.cellMap[cell]
        // Within a cell: bits 0..2 → copy offset, bits 3..5 → insert offset.
        let copyOffset = symbol & 7
        let insertOffset = (symbol >> 3) & 7
        let insertCode = insertBaseRange + insertOffset
        let copyCode = copyBaseRange + copyOffset
        return (insertCode, copyCode, useDist)
    }

    /// § 5 Table 4 cell map. Indexed by `symbol >> 6` (0..10). Each
    /// entry is `(insert-base, copy-base, useDistance)`.
    ///
    /// Layout per the spec table:
    /// ```
    ///   cell 0  (sym 0..63):    insert 0..7,    copy 0..7,    useDist=false
    ///   cell 1  (sym 64..127):  insert 0..7,    copy 8..15,   useDist=false
    ///   cell 2  (sym 128..191): insert 0..7,    copy 0..7,    useDist=true
    ///   cell 3  (sym 192..255): insert 0..7,    copy 8..15,   useDist=true
    ///   cell 4  (sym 256..319): insert 8..15,   copy 0..7,    useDist=true
    ///   cell 5  (sym 320..383): insert 8..15,   copy 8..15,   useDist=true
    ///   cell 6  (sym 384..447): insert 0..7,    copy 16..23,  useDist=true
    ///   cell 7  (sym 448..511): insert 16..23,  copy 0..7,    useDist=true
    ///   cell 8  (sym 512..575): insert 8..15,   copy 16..23,  useDist=true
    ///   cell 9  (sym 576..639): insert 16..23,  copy 8..15,   useDist=true
    ///   cell 10 (sym 640..703): insert 16..23,  copy 16..23,  useDist=true
    /// ```
    static let cellMap: [(insertBase: Int, copyBase: Int, useDistance: Bool)] = [
        (0,   0,  false),
        (0,   8,  false),
        (0,   0,  true),
        (0,   8,  true),
        (8,   0,  true),
        (8,   8,  true),
        (0,  16,  true),
        (16,  0,  true),
        (8,  16,  true),
        (16,  8,  true),
        (16, 16,  true),
    ]
}
