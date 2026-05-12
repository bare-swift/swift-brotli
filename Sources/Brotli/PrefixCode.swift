// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// RFC 7932 § 3.4 (simple) + § 3.5 (complex) prefix codes.
///
/// A `PrefixCode` is a canonical Huffman code over an alphabet of size
/// `n`. It is constructed once per declaration in the meta-block prefix,
/// then queried symbol-by-symbol via ``readSymbol(_:)``.
///
/// Internally we store the canonical-code data sorted by `(length,
/// symbol)`. Decoding reads bits one at a time, accumulating an
/// MSB-first canonical-code value, and checks at each step whether any
/// symbol of the just-completed length matches.
struct PrefixCode {
    /// Maximum code length for "normal" alphabets (literal, IC, distance,
    /// etc.). Per RFC 7932 § 3.5 the canonical Huffman cap is 15.
    static let maxNormalBits = 15
    /// Code-length code (§ 3.5) caps at 5 bits.
    static let maxCodeLengthBits = 5

    /// Single-symbol shortcut: when the alphabet has exactly one used
    /// symbol, that symbol is returned by ``readSymbol(_:)`` with zero
    /// bits read.
    private let singleSymbol: Int?

    /// `codeStart[L]` = first canonical-code value at length L (MSB-first).
    /// `codeEnd[L]`   = `codeStart[L] + bl_count[L]`.
    /// `symbolStart[L]` = offset into `symbolsByLength` of first symbol at length L.
    private let codeStart: [UInt32]
    private let codeEnd: [UInt32]
    private let symbolStart: [Int]
    private let symbolsByLength: [Int]
    private let maxBitsInUse: Int

    /// Construct from an explicit `lengths` array (parallel to alphabet
    /// symbols). Lengths must be ≤ `maxBits`. Throws if the code is
    /// over- or under-subscribed.
    init(lengths: [Int], maxBits: Int) throws(BrotliError) {
        // Verify Kraft inequality (canonical Huffman correctness).
        var blCount = [Int](repeating: 0, count: maxBits + 1)
        for L in lengths {
            guard L >= 0 && L <= maxBits else { throw BrotliError.invalidPrefixCode }
            blCount[L] += 1
        }
        // Special case: exactly one symbol with length > 0 OR a "zero-length
        // code" with exactly one symbol of length 0 is treated as a single-
        // symbol code per § 3.4 (NSYM=1) and § 3.5 (single non-zero length).
        let nonZeroCount = blCount[1...].reduce(0, +)
        if nonZeroCount == 0 {
            // No non-zero symbols → look for a zero-length single symbol.
            var sym: Int? = nil
            for (i, L) in lengths.enumerated() where L == 0 {
                if sym == nil { sym = i } else { sym = nil; break }
            }
            // If multiple zero-length symbols, no actual single-symbol code.
            self.singleSymbol = (lengths.count == 1) ? sym : nil
            self.codeStart = []
            self.codeEnd = []
            self.symbolStart = []
            self.symbolsByLength = []
            self.maxBitsInUse = 0
            if self.singleSymbol == nil {
                throw BrotliError.invalidPrefixCode
            }
            return
        }
        if nonZeroCount == 1 {
            // Exactly one symbol with non-zero length (or one symbol with len=1
            // in a degenerate case) → single-symbol code.
            var sym = 0
            for (i, L) in lengths.enumerated() where L != 0 {
                sym = i
                break
            }
            self.singleSymbol = sym
            self.codeStart = []
            self.codeEnd = []
            self.symbolStart = []
            self.symbolsByLength = []
            self.maxBitsInUse = 0
            return
        }
        // General canonical Huffman construction per RFC 1951 § 3.2.2.
        // Zero-length symbols don't participate in the code; force blCount[0]
        // to 0 so the (code + blCount[bits-1]) << 1 recurrence starts cleanly
        // at bits=1.
        blCount[0] = 0
        var nextCode = [UInt32](repeating: 0, count: maxBits + 2)
        var code: UInt32 = 0
        for bits in 1...maxBits {
            code = (code + UInt32(blCount[bits - 1])) << 1
            nextCode[bits] = code
        }
        // Verify Kraft equality (canonical codes must use the full space).
        let lastCode = nextCode[maxBits] + UInt32(blCount[maxBits])
        if lastCode != (UInt32(1) << maxBits) {
            // Under-subscribed (or over-subscribed; latter caught above by len > maxBits).
            // BUT: a single-symbol code with length L > 0 has the next-code
            // slot 1 short, and that's been handled by the nonZeroCount == 1 case.
            // Anything else here is an error.
            throw BrotliError.invalidPrefixCode
        }

        // Build (length, symbol) sorted list and the start indices.
        var pairs: [(L: Int, S: Int)] = []
        pairs.reserveCapacity(nonZeroCount)
        for (i, L) in lengths.enumerated() where L != 0 {
            pairs.append((L: L, S: i))
        }
        pairs.sort { ($0.L, $0.S) < ($1.L, $1.S) }

        var sStart = [Int](repeating: 0, count: maxBits + 2)
        var cStart = [UInt32](repeating: 0, count: maxBits + 2)
        var cEnd = [UInt32](repeating: 0, count: maxBits + 2)
        // Recompute next_code per length to derive code ranges.
        var nc = nextCode  // copy
        for L in 1...maxBits {
            cStart[L] = nc[L]
            cEnd[L] = nc[L] + UInt32(blCount[L])
        }
        // Compute symbolStart via cumulative counts.
        var cum = 0
        for L in 1...maxBits {
            sStart[L] = cum
            cum += blCount[L]
        }

        var maxL = 0
        for L in (1...maxBits).reversed() where blCount[L] > 0 {
            maxL = L
            break
        }

        self.singleSymbol = nil
        self.codeStart = cStart
        self.codeEnd = cEnd
        self.symbolStart = sStart
        self.symbolsByLength = pairs.map { $0.S }
        self.maxBitsInUse = maxL
    }

    /// Decode one symbol from the bit stream.
    func readSymbol(_ r: inout BitReader) throws(BrotliError) -> Int {
        if let s = singleSymbol { return s }
        var acc: UInt32 = 0
        for L in 1...maxBitsInUse {
            let bit = try r.readBit()
            acc = (acc << 1) | bit
            if acc >= codeStart[L] && acc < codeEnd[L] {
                let offset = Int(acc - codeStart[L])
                return symbolsByLength[symbolStart[L] + offset]
            }
        }
        throw BrotliError.invalidPrefixCode
    }

    // MARK: - Reading prefix-code declarations from the bit stream

    /// Read a prefix-code declaration per RFC 7932 § 3.4 / § 3.5.
    /// `alphabetSize` is e.g. 256 for literals, 704 for insert-and-copy.
    /// `maxBits` defaults to `maxNormalBits` (15) but is 5 for the code-
    /// length code.
    static func read(
        _ r: inout BitReader,
        alphabetSize: Int,
        maxBits: Int = PrefixCode.maxNormalBits
    ) throws(BrotliError) -> PrefixCode {
        // First 2 bits: 01 → simple form (§ 3.4); 00/10/11 → complex form
        // (§ 3.5) with HSKIP = that 2-bit value (must be 0, 2, or 3).
        let selector = try r.readBits(2)
        if selector == 1 {
            return try readSimple(&r, alphabetSize: alphabetSize, maxBits: maxBits)
        }
        let hskip = Int(selector)
        if hskip != 0 && hskip != 2 && hskip != 3 {
            // HSKIP=1 is the simple-form selector; anything else is an error
            // in the 2-bit value space (which we already excluded).
            throw BrotliError.invalidPrefixCode
        }
        return try readComplex(&r, hskip: hskip, alphabetSize: alphabetSize, maxBits: maxBits)
    }

    private static func readSimple(
        _ r: inout BitReader,
        alphabetSize: Int,
        maxBits: Int
    ) throws(BrotliError) -> PrefixCode {
        let nsym = Int(try r.readBits(2)) + 1   // 1..4
        let alphabetBits = bitsToHold(alphabetSize - 1)
        var symbols: [Int] = []
        symbols.reserveCapacity(nsym)
        for _ in 0..<nsym {
            let s = Int(try r.readBits(alphabetBits))
            if s >= alphabetSize {
                throw BrotliError.invalidPrefixCode
            }
            if symbols.contains(s) {
                throw BrotliError.invalidPrefixCode
            }
            symbols.append(s)
        }
        // Per § 3.4: prefix codes of the same bit length are assigned to
        // symbols in sorted order. We must therefore sort symbols ascending.
        symbols.sort()

        var lengths = [Int](repeating: 0, count: alphabetSize)
        switch nsym {
        case 1:
            // Length 0 — zero-bit code.
            lengths[symbols[0]] = 0
            // Build via single-symbol shortcut path. We need at least one
            // entry with length 0 AND alphabet of size 1 — but the alphabet
            // is larger. So construct manually and short-circuit.
            return try makeSingleSymbol(symbols[0], alphabetSize: alphabetSize, maxBits: maxBits)
        case 2:
            lengths[symbols[0]] = 1
            lengths[symbols[1]] = 1
        case 3:
            lengths[symbols[0]] = 1
            lengths[symbols[1]] = 2
            lengths[symbols[2]] = 2
        case 4:
            let treeSelect = try r.readBit()
            if treeSelect == 0 {
                lengths[symbols[0]] = 2
                lengths[symbols[1]] = 2
                lengths[symbols[2]] = 2
                lengths[symbols[3]] = 2
            } else {
                lengths[symbols[0]] = 1
                lengths[symbols[1]] = 2
                lengths[symbols[2]] = 3
                lengths[symbols[3]] = 3
            }
        default:
            throw BrotliError.invalidPrefixCode
        }
        return try PrefixCode(lengths: lengths, maxBits: maxBits)
    }

    static func makeSingleSymbol(_ s: Int, alphabetSize: Int, maxBits: Int) throws(BrotliError) -> PrefixCode {
        var lengths = [Int](repeating: 0, count: alphabetSize)
        // Use length 1 for the single non-zero symbol so the standard
        // construction succeeds; readSymbol will short-circuit via
        // singleSymbol regardless.
        lengths[s] = 1
        return try PrefixCode(lengths: lengths, maxBits: maxBits)
    }

    /// Read a complex prefix code (§ 3.5).
    private static func readComplex(
        _ r: inout BitReader,
        hskip: Int,
        alphabetSize: Int,
        maxBits: Int
    ) throws(BrotliError) -> PrefixCode {
        // Step 1: Read code-length-code lengths (18 symbols, order per § 3.5;
        // first HSKIP entries are implicit zeros). Each is read via the
        // variable-length meta-code (see decodeMetaLength).
        var clLengths = [Int](repeating: 0, count: 18)
        // Track running "non-zero count" to know when to stop.
        var checksum = 0  // sum of (32 >> code_length) over non-zero entries
        var index = hskip
        while index < 18 {
            let len = try decodeMetaLength(&r)
            clLengths[Self.codeLengthCodeOrder[index]] = len
            index += 1
            if len > 0 {
                checksum += 32 >> len
                if checksum >= 32 { break }
            }
        }
        if index > 18 || (index < 18 && checksum != 32) {
            // Either we ran past the end without hitting checksum=32, or
            // we filled exactly 18 without reaching it.
            if checksum != 32 { throw BrotliError.invalidPrefixCode }
        }

        // Build the code-length code.
        let clCode = try PrefixCode(lengths: clLengths, maxBits: PrefixCode.maxCodeLengthBits)

        // Step 2: Read the actual alphabet's code lengths using clCode.
        // Total symbols expected = alphabetSize.
        var alphabetLengths = [Int](repeating: 0, count: alphabetSize)
        var i = 0
        var prevNonZeroLen = 8  // Default per § 3.5.
        var prevRepeatSym = -1  // last symbol-emitted in the {16, 17} chain (-1 if none)
        var prevRepeatCount = 0 // running count from chained 16s or 17s
        var symSum: UInt32 = 0  // Kraft-style sum of (32768 >> L) over emitted non-zero lengths
        while i < alphabetSize {
            let sym = try clCode.readSymbol(&r)
            switch sym {
            case 0...15:
                alphabetLengths[i] = sym
                i += 1
                if sym > 0 {
                    prevNonZeroLen = sym
                    symSum += UInt32(32768) >> sym
                }
                prevRepeatSym = -1
                prevRepeatCount = 0
            case 16:
                let extra = Int(try r.readBits(2))
                let newCount: Int
                let oldChainCount: Int
                if prevRepeatSym == 16 {
                    newCount = 4 * (prevRepeatCount - 2) + 3 + extra
                    oldChainCount = prevRepeatCount
                } else {
                    newCount = 3 + extra
                    oldChainCount = 0  // chain reset
                }
                let emit = newCount - oldChainCount
                if emit <= 0 { throw BrotliError.invalidPrefixCode }
                for _ in 0..<emit {
                    if i >= alphabetSize { throw BrotliError.invalidPrefixCode }
                    alphabetLengths[i] = prevNonZeroLen
                    i += 1
                    symSum += UInt32(32768) >> prevNonZeroLen
                }
                prevRepeatSym = 16
                prevRepeatCount = newCount
            case 17:
                let extra = Int(try r.readBits(3))
                let newCount: Int
                let oldChainCount: Int
                if prevRepeatSym == 17 {
                    newCount = 8 * (prevRepeatCount - 2) + 3 + extra
                    oldChainCount = prevRepeatCount
                } else {
                    newCount = 3 + extra
                    oldChainCount = 0  // chain reset
                }
                let emit = newCount - oldChainCount
                if emit <= 0 { throw BrotliError.invalidPrefixCode }
                for _ in 0..<emit {
                    if i >= alphabetSize { throw BrotliError.invalidPrefixCode }
                    alphabetLengths[i] = 0
                    i += 1
                }
                prevRepeatSym = 17
                prevRepeatCount = newCount
            default:
                throw BrotliError.invalidPrefixCode
            }
            // Early exit on Kraft-completion.
            if symSum == 32768 {
                break
            }
            if symSum > 32768 {
                throw BrotliError.invalidPrefixCode
            }
        }
        // Trailing positions are implicit zero (already initialized).
        return try PrefixCode(lengths: alphabetLengths, maxBits: maxBits)
    }

    /// Variable-length meta-Huffman from § 3.5 decoding a value 0..5.
    /// Tree (stream-LSB-first):
    ///   bit 0:
    ///     0 → bit 1:
    ///       0 → 0  (2 bits: 00)
    ///       1 → 3  (2 bits: 01)
    ///     1 → bit 1:
    ///       0 → 4  (2 bits: 10)
    ///       1 → bit 2:
    ///         0 → 2  (3 bits: 110)
    ///         1 → bit 3:
    ///           0 → 1  (4 bits: 1110)
    ///           1 → 5  (4 bits: 1111)
    private static func decodeMetaLength(_ r: inout BitReader) throws(BrotliError) -> Int {
        let b0 = try r.readBit()
        if b0 == 0 {
            let b1 = try r.readBit()
            return (b1 == 0) ? 0 : 3
        }
        let b1 = try r.readBit()
        if b1 == 0 { return 4 }
        let b2 = try r.readBit()
        if b2 == 0 { return 2 }
        let b3 = try r.readBit()
        return (b3 == 0) ? 1 : 5
    }

    // MARK: - Helpers

    /// Code-length-code symbol ordering per RFC 7932 § 3.5.
    static let codeLengthCodeOrder: [Int] = [
        1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    ]

    /// Number of bits required to hold any value in 0...maxValue.
    static func bitsToHold(_ maxValue: Int) -> Int {
        if maxValue <= 0 { return 1 }
        var v = maxValue
        var bits = 0
        while v > 0 { v >>= 1; bits += 1 }
        return bits
    }
}
