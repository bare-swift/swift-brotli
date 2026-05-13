// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// Length-limited canonical Huffman builder. Frequencies → code lengths
/// (with cap) → canonical codes per RFC 1951 § 3.2.2 (which RFC 7932
/// inherits for its prefix-code form).
///
/// Algorithm: package-merge (Larmore-Hirschberg, 1990) for the
/// length-limited step. Simple and provably optimal for the bounded-depth
/// case; O(n·maxBits) which is fine for brotli's small alphabets
/// (≤704 symbols).
enum HuffmanBuilder {
    /// Build canonical code lengths from symbol frequencies.
    ///
    /// - Parameters:
    ///   - frequencies: per-symbol counts. Zero means symbol unused.
    ///   - maxBits: cap on any returned length. Brotli uses 15.
    /// - Returns: lengths per symbol; 0 for unused symbols.
    ///   - All-zero frequencies → all zeros.
    ///   - Exactly one non-zero → length 1 at that index, 0 elsewhere.
    ///   - Two or more non-zero → length-limited canonical lengths.
    static func build(frequencies: [Int], maxBits: Int) -> [Int] {
        let n = frequencies.count
        var lengths = [Int](repeating: 0, count: n)

        let used: [(symbol: Int, freq: Int)] = frequencies.enumerated()
            .compactMap { (i, f) in f > 0 ? (i, f) : nil }
        if used.isEmpty { return lengths }
        if used.count == 1 {
            lengths[used[0].symbol] = 1
            return lengths
        }
        if used.count == 2 {
            lengths[used[0].symbol] = 1
            lengths[used[1].symbol] = 1
            return lengths
        }

        // Package-merge. At each iteration, pair adjacent items in
        // `packages` into "packages of two", then merge with the sorted
        // `initial` symbol list.
        struct Item {
            var weight: Int
            var symbols: [Int]
        }
        let initial: [Item] = used
            .sorted { $0.freq < $1.freq }
            .map { Item(weight: $0.freq, symbols: [$0.symbol]) }

        var packages = initial
        for _ in 1..<maxBits {
            var newPackages: [Item] = []
            var i = 0
            while i + 1 < packages.count {
                newPackages.append(Item(
                    weight: packages[i].weight + packages[i+1].weight,
                    symbols: packages[i].symbols + packages[i+1].symbols
                ))
                i += 2
            }
            var merged: [Item] = []
            merged.reserveCapacity(newPackages.count + initial.count)
            var a = 0, b = 0
            while a < newPackages.count && b < initial.count {
                if newPackages[a].weight <= initial[b].weight {
                    merged.append(newPackages[a]); a += 1
                } else {
                    merged.append(initial[b]); b += 1
                }
            }
            while a < newPackages.count { merged.append(newPackages[a]); a += 1 }
            while b < initial.count { merged.append(initial[b]); b += 1 }
            packages = merged
        }

        let solutionCount = 2 * (used.count - 1)
        let solution = packages.prefix(solutionCount)
        for item in solution {
            for sym in item.symbols {
                lengths[sym] += 1
            }
        }

        for i in 0..<n where lengths[i] > maxBits {
            lengths[i] = maxBits
        }

        return lengths
    }

    /// Compute canonical Huffman codes from a code-length array.
    /// RFC 1951 § 3.2.2 algorithm, with `bl_count[0] = 0` reset.
    /// Returns MSB-first code numeric values; bit-reverse at emit time.
    static func canonicalCodes(from lengths: [Int]) -> [UInt32] {
        let n = lengths.count
        var codes = [UInt32](repeating: 0, count: n)
        if n == 0 { return codes }

        let maxLen = lengths.max() ?? 0
        if maxLen == 0 { return codes }

        var blCount = [Int](repeating: 0, count: maxLen + 1)
        for L in lengths where L > 0 { blCount[L] += 1 }
        blCount[0] = 0  // RFC 1951 § 3.2.2 reset

        var nextCode = [UInt32](repeating: 0, count: maxLen + 1)
        var code: UInt32 = 0
        for bits in 1...maxLen {
            code = (code + UInt32(blCount[bits - 1])) << 1
            nextCode[bits] = code
        }

        for i in 0..<n {
            let L = lengths[i]
            if L > 0 {
                codes[i] = nextCode[L]
                nextCode[L] += 1
            }
        }
        return codes
    }
}
