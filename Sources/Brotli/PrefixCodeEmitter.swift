// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// Emits a prefix-code descriptor into a ``BitWriter`` per RFC 7932 § 3.4-3.5.
///
/// - **Simple form** (§ 3.4): 1..4 distinct symbols. Selector bits "01"
///   LSB-first (writeBits(1, count: 2)).
/// - **Complex form** (§ 3.5): ≥ 5 distinct symbols. Selector bits "00"
///   (HSKIP=0). Followed by 18 length-code-lengths in the code-length-code
///   order, then the alphabet's code-lengths emitted via the meta-Huffman
///   tree those length-code-lengths declare.
///
/// v0.2 chooses simple when ≤4 distinct used symbols, complex otherwise.
/// v0.2 always uses HSKIP=0 (emit all 18 length-code-lengths). v0.2 does
/// NOT use run codes 16/17 — every alphabet code-length is emitted
/// literally. Suboptimal but valid.
enum PrefixCodeEmitter {
    /// Length-symbol order for the complex form's HCLENS table per RFC 7932 § 3.5.
    static let lengthCodeOrder: [Int] = [
        1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    ]

    static func emit(codeLengths: [Int], alphabetSize: Int, to w: inout BitWriter) {
        let used = codeLengths.enumerated().filter { $0.element > 0 }
        if used.count <= 4 {
            emitSimple(codeLengths: codeLengths, alphabetSize: alphabetSize,
                       used: used.map(\.offset), to: &w)
        } else {
            emitComplex(codeLengths: codeLengths, to: &w)
        }
    }

    // MARK: - Simple form (RFC 7932 § 3.4)
    private static func emitSimple(
        codeLengths: [Int],
        alphabetSize: Int,
        used: [Int],
        to w: inout BitWriter
    ) {
        // Selector "01" LSB-first = writeBits(1, count: 2).
        w.writeBits(1, count: 2)
        // NSYM - 1 (2 bits).
        let nsym = used.count
        precondition(nsym >= 1 && nsym <= 4)
        w.writeBits(UInt32(nsym - 1), count: 2)
        // Symbols ascending (reader sorts post-read, but per § 3.4 the
        // emit order matches sorted order for canonical assignment).
        let symBits = bitsToHold(alphabetSize - 1)
        let sortedSymbols = used.sorted()
        for sym in sortedSymbols {
            w.writeBits(UInt32(sym), count: symBits)
        }
        // NSYM == 4 has a 1-bit tree-select suffix. v0.2 picks tree-select=0
        // (the balanced 4-symbol tree where all codes have length 2). The
        // caller's HuffmanBuilder would only produce all-length-2 for 4
        // equally-frequent symbols; mixed-frequency 4-symbol cases produce
        // (1, 2, 3, 3) which need tree-select=1.
        if nsym == 4 {
            // Inspect the actual code-lengths to choose tree-select.
            // tree-select=0 ⇔ all four lengths are 2.
            // tree-select=1 ⇔ lengths are (1, 2, 3, 3) in sorted-symbol order.
            let firstLen = codeLengths[sortedSymbols[0]]
            if firstLen == 1 {
                w.writeBit(1)  // tree-select=1: lengths (1, 2, 3, 3)
            } else {
                w.writeBit(0)  // tree-select=0: all length 2
            }
        }
    }

    // MARK: - Complex form (RFC 7932 § 3.5)
    private static func emitComplex(codeLengths: [Int], to w: inout BitWriter) {
        // Selector "00" LSB-first = writeBits(0, count: 2). HSKIP=0.
        w.writeBits(0, count: 2)

        // Build meta-Huffman tree over the length-code alphabet 0..17.
        // v0.2 doesn't use repeat codes 16/17, so their frequency is 0.
        var lengthCodeFreqs = [Int](repeating: 0, count: 18)
        for L in codeLengths { lengthCodeFreqs[L] += 1 }

        // Per RFC 7932 § 3.5, length-code lengths cap at 5.
        let lengthCodeLengths = HuffmanBuilder.build(
            frequencies: lengthCodeFreqs, maxBits: 5
        )

        // Emit length-code-lengths in codeLengthCodeOrder. Each length is
        // encoded via the variable-length meta-meta-code from § 3.5 Table 1
        // (mirrors `PrefixCode.decodeMetaLength`).
        //
        // Reader stops at Kraft checksum 32; we must stop emitting at the
        // same point so subsequent reads land on the alphabet code-length
        // stream (not on leftover length-code-length codes).
        var clChecksum = 0
        for sym in lengthCodeOrder {
            let L = lengthCodeLengths[sym]
            emitLengthCodeLength(L, to: &w)
            if L > 0 {
                clChecksum += 32 >> L
                if clChecksum >= 32 { break }
            }
        }

        // Build canonical codes for the meta-Huffman tree.
        let lengthCodeCodes = HuffmanBuilder.canonicalCodes(from: lengthCodeLengths)

        // Emit alphabet code-lengths sequentially. Reader has an early-exit
        // when Kraft sum reaches 32768; if HuffmanBuilder produced a valid
        // canonical code that satisfies Kraft, all non-zero entries get
        // emitted and trailing zeros are implicit.
        //
        // We track Kraft and stop emitting once it reaches 32768, so the
        // bit stream matches what the reader expects.
        var symSum: UInt32 = 0
        for L in codeLengths {
            // Emit the meta-Huffman code for length L.
            let code = lengthCodeCodes[L]
            let bits = lengthCodeLengths[L]
            // Canonical codes are MSB-first numerically; bit-reverse to
            // LSB-first wire order so the LSB-first BitReader + MSB-first
            // accumulator pattern reconstructs the canonical numeric value.
            w.writeBits(reverseBits(code, count: bits), count: bits)
            if L > 0 {
                symSum &+= UInt32(32768) >> L
                if symSum == 32768 { break }
            }
        }
    }

    /// Emit the meta-meta-code for length L per RFC 7932 § 3.5 Table 1.
    /// These are NOT canonical Huffman — they're the hand-crafted variable
    /// codes that `PrefixCode.decodeMetaLength` decodes.
    ///
    /// Bit patterns (LSB-first wire order, matching decoder):
    ///   length 0 → "00"   (2 bits)
    ///   length 1 → "1110" (4 bits)
    ///   length 2 → "110"  (3 bits)
    ///   length 3 → "01"   (2 bits)
    ///   length 4 → "10"   (2 bits)
    ///   length 5 → "1111" (4 bits)
    ///
    /// As writeBits-numeric values (bit0 = LSB of value goes first):
    ///   length 0 → (0, 2)
    ///   length 1 → (0b0111, 4)
    ///   length 2 → (0b011, 3)
    ///   length 3 → (0b10, 2)
    ///   length 4 → (0b01, 2)
    ///   length 5 → (0b1111, 4)
    private static func emitLengthCodeLength(_ L: Int, to w: inout BitWriter) {
        let (value, bits): (UInt32, Int) = {
            switch L {
            case 0: return (0b00, 2)
            case 1: return (0b0111, 4)
            case 2: return (0b011, 3)
            case 3: return (0b10, 2)
            case 4: return (0b01, 2)
            case 5: return (0b1111, 4)
            default:
                preconditionFailure("length-code length \(L) out of range 0..5")
            }
        }()
        w.writeBits(value, count: bits)
    }

    /// Reverse the low `count` bits of `x`.
    static func reverseBits(_ x: UInt32, count: Int) -> UInt32 {
        var v = x
        var r: UInt32 = 0
        for _ in 0..<count {
            r = (r << 1) | (v & 1)
            v >>= 1
        }
        return r
    }

    /// Number of bits needed to hold `maxValue` (1 if maxValue==0).
    static func bitsToHold(_ maxValue: Int) -> Int {
        if maxValue <= 0 { return 1 }
        var n = 0
        var v = maxValue
        while v > 0 { n += 1; v >>= 1 }
        return n
    }
}
