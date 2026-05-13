// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// One unit of work the encoder emits: an `insert` (literals to copy
/// verbatim) plus optionally a `copy` (backreference of `copyLen` bytes
/// at `distance` bytes back).
///
/// `copyLen` is 0 for the FINAL command in a literal-only stream — the
/// decoder will fill its output buffer to `MLEN` from the literals and
/// break before reading the distance code. Otherwise `copyLen` must be
/// in 2...(2^24-1) per RFC 7932 § 5.
struct EncoderCommand {
    var insertLits: [UInt8]
    var copyLen: Int
    var distance: Int
}

/// Insert / copy / distance length-bracket lookups + combined-symbol
/// encoding per RFC 7932 § 4-5.
///
/// v0.2 uses NPOSTFIX=0, NDIRECT=0, and always emits distance codes for
/// real copies (useDistance=true). The literal-only quality-0 path uses
/// a synthesized "insert = N, copy = 2" pattern; the decoder breaks the
/// loop after literals exhaust `MLEN` so the dummy copy is never executed.
enum EncoderCommandCoding {
    // MARK: - Insert / copy length brackets (mirror v0.1 `InsertCopy`).

    /// Per RFC 7932 § 5 — 24 insert-length brackets.
    static let insertBase: [Int] = [
        0, 1, 2, 3, 4, 5, 6, 8, 10, 14, 18, 26, 34, 50, 66, 98,
        130, 194, 322, 578, 1090, 2114, 6210, 22594,
    ]
    static let insertExtraBits: [Int] = [
        0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5,
        6, 7, 8, 9, 10, 12, 14, 24,
    ]

    /// Per RFC 7932 § 5 — 24 copy-length brackets.
    static let copyBase: [Int] = [
        2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 18, 22, 30, 38, 54,
        70, 102, 134, 198, 326, 582, 1094, 2118,
    ]
    static let copyExtraBits: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4,
        5, 5, 6, 7, 8, 9, 10, 24,
    ]

    /// Find the insert-length bracket containing `len`.
    static func insertLengthCode(_ len: Int) -> (code: Int, extra: UInt32, extraBits: Int) {
        precondition(len >= 0)
        for i in stride(from: insertBase.count - 1, through: 0, by: -1) {
            if len >= insertBase[i] {
                return (i, UInt32(len - insertBase[i]), insertExtraBits[i])
            }
        }
        preconditionFailure("insert length \(len) below 0")
    }

    /// Find the copy-length bracket containing `len` (must be ≥ 2).
    static func copyLengthCode(_ len: Int) -> (code: Int, extra: UInt32, extraBits: Int) {
        precondition(len >= 2)
        for i in stride(from: copyBase.count - 1, through: 0, by: -1) {
            if len >= copyBase[i] {
                return (i, UInt32(len - copyBase[i]), copyExtraBits[i])
            }
        }
        preconditionFailure("copy length \(len) below 2")
    }

    // MARK: - Combined insert-and-copy symbol (RFC 7932 § 5 Table 4).

    /// Compute the 0..703 insert-and-copy symbol for the given codes.
    ///
    /// Inverts the decomposition in `InsertCopy.decompose`. v0.2 always
    /// passes `useDistance=true` (we don't use the ring-buffer reuse path).
    static func combinedSymbol(insertCode: Int, copyCode: Int, useDistance: Bool) -> Int {
        precondition(insertCode >= 0 && insertCode < 24)
        precondition(copyCode >= 0 && copyCode < 24)

        // Bucket insertCode into one of {0, 8, 16}.
        let (insertBaseBucket, insertOffset): (Int, Int)
        switch insertCode {
        case 0...7: (insertBaseBucket, insertOffset) = (0, insertCode)
        case 8...15: (insertBaseBucket, insertOffset) = (8, insertCode - 8)
        case 16...23: (insertBaseBucket, insertOffset) = (16, insertCode - 16)
        default: preconditionFailure("insertCode out of range")
        }
        let (copyBaseBucket, copyOffset): (Int, Int)
        switch copyCode {
        case 0...7: (copyBaseBucket, copyOffset) = (0, copyCode)
        case 8...15: (copyBaseBucket, copyOffset) = (8, copyCode - 8)
        case 16...23: (copyBaseBucket, copyOffset) = (16, copyCode - 16)
        default: preconditionFailure("copyCode out of range")
        }

        // Map (insertBaseBucket, copyBaseBucket, useDistance) → cell index.
        // v0.1 InsertCopy.cellMap:
        //   cell 0  (insert 0, copy 0,  useDist=false)
        //   cell 1  (insert 0, copy 8,  useDist=false)
        //   cell 2  (insert 0, copy 0,  useDist=true)
        //   cell 3  (insert 0, copy 8,  useDist=true)
        //   cell 4  (insert 8, copy 0,  useDist=true)
        //   cell 5  (insert 8, copy 8,  useDist=true)
        //   cell 6  (insert 0, copy 16, useDist=true)
        //   cell 7  (insert 16, copy 0, useDist=true)
        //   cell 8  (insert 8, copy 16, useDist=true)
        //   cell 9  (insert 16, copy 8, useDist=true)
        //   cell 10 (insert 16, copy 16, useDist=true)
        let cell: Int
        switch (insertBaseBucket, copyBaseBucket, useDistance) {
        case (0, 0, false): cell = 0
        case (0, 8, false): cell = 1
        case (0, 0, true): cell = 2
        case (0, 8, true): cell = 3
        case (8, 0, true): cell = 4
        case (8, 8, true): cell = 5
        case (0, 16, true): cell = 6
        case (16, 0, true): cell = 7
        case (8, 16, true): cell = 8
        case (16, 8, true): cell = 9
        case (16, 16, true): cell = 10
        default:
            // useDist=false only exists for cells 0/1 (insert 0..7).
            preconditionFailure("(\(insertBaseBucket), \(copyBaseBucket), \(useDistance)) has no cell")
        }

        return cell * 64 + insertOffset * 8 + copyOffset
    }

    // MARK: - Distance code (RFC 7932 § 4 with NPOSTFIX=0, NDIRECT=0).

    /// Encode a positive distance into (code, extraBits payload, extraBits count).
    ///
    /// For NPOSTFIX=0, NDIRECT=0:
    ///   - Codes 0..15: short-distance ring-buffer references (NOT emitted by v0.2).
    ///   - Codes 16+j: direct distances. For j in 0...:
    ///     NDISTBITS = 1 + (j >> 1)
    ///     DOFFSET = ((2 + (j & 1)) << NDISTBITS) - 4
    ///     distance = DOFFSET + extra + 1, where extra ∈ [0, 2^NDISTBITS - 1]
    static func distanceCode(_ distance: Int) -> (code: Int, extra: UInt32, extraBits: Int) {
        precondition(distance >= 1)
        var j = 0
        while j < 48 {
            let ndistBits = 1 + (j >> 1)
            let doffset = ((2 + (j & 1)) << ndistBits) - 4
            let bracketLow = doffset + 1
            let bracketHigh = doffset + (1 << ndistBits)
            if distance >= bracketLow && distance <= bracketHigh {
                return (16 + j, UInt32(distance - bracketLow), ndistBits)
            }
            j += 1
        }
        preconditionFailure("distance \(distance) out of representable range")
    }
}
