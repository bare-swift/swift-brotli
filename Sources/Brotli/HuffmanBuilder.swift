// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// Length-limited canonical Huffman builder. Frequencies → code lengths
/// (with cap) → canonical codes per RFC 1951 § 3.2.2 (which RFC 7932
/// inherits for its prefix-code form).
///
/// Algorithm: bottom-up Huffman via repeated min-pair merging on a
/// frequency-sorted list. Optimal for n ≤ 2^maxBits with no constraint
/// binding (which is always true for brotli alphabets: 256 / 64 / 704
/// symbols at maxBits=15, and 18 at maxBits=5).
///
/// If the natural Huffman would exceed `maxBits`, lengths are
/// post-processed by lowering deep symbols and raising shallow ones
/// until all lengths fit, while preserving Kraft equality.
enum HuffmanBuilder {
    /// Build canonical code lengths from symbol frequencies.
    ///
    /// - Parameters:
    ///   - frequencies: per-symbol counts. Zero means symbol unused.
    ///   - maxBits: cap on any returned length (brotli uses 15; the
    ///     length-code meta-tree uses 5).
    /// - Returns: lengths per symbol; 0 for unused symbols.
    ///   - All-zero frequencies → all zeros.
    ///   - Exactly one non-zero → length 1 at that index.
    ///   - Two or more non-zero → length-limited canonical lengths,
    ///     satisfying Kraft equality (Σ 2^-L = 1).
    static func build(frequencies: [Int], maxBits: Int) -> [Int] {
        let n = frequencies.count
        var lengths = [Int](repeating: 0, count: n)

        // Collect used (symbol, freq) pairs.
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

        // Bottom-up Huffman. Each tree node has either a single original
        // symbol or two children. We track which original symbols are
        // contained, and the depth (length) is computed by walking the
        // tree top-down once it's built.
        //
        // Use a simple node-list with O(n^2) min-pair selection — fine
        // for n ≤ 704.
        struct Node {
            var weight: Int
            var symbols: [Int]  // original symbols this subtree contains
        }
        var pool: [Node] = used.map { Node(weight: $0.freq, symbols: [$0.symbol]) }

        // Build the tree by repeated min-pair merging.
        while pool.count > 1 {
            // Find indices of the two smallest-weight nodes.
            var minA = 0
            var minB = 1
            if pool[minA].weight > pool[minB].weight { swap(&minA, &minB) }
            for i in 2..<pool.count {
                if pool[i].weight < pool[minA].weight {
                    minB = minA
                    minA = i
                } else if pool[i].weight < pool[minB].weight {
                    minB = i
                }
            }
            // Merge.
            let merged = Node(
                weight: pool[minA].weight + pool[minB].weight,
                symbols: pool[minA].symbols + pool[minB].symbols
            )
            // Remove in descending index order to keep indices valid.
            let (hi, lo) = (max(minA, minB), min(minA, minB))
            pool.remove(at: hi)
            pool.remove(at: lo)
            pool.append(merged)
            // For each original symbol that ended up in this merged node,
            // increment its current depth-so-far. We track depths in
            // `lengths` (length = depth in the final tree).
            for sym in merged.symbols {
                lengths[sym] += 1
            }
        }

        // Cap lengths at maxBits if any exceed (rare for our alphabet sizes).
        if lengths.contains(where: { $0 > maxBits }) {
            lengths = limitToMaxBits(lengths, maxBits: maxBits)
        }

        return lengths
    }

    /// Cap any code length > maxBits, preserving Kraft equality by
    /// transferring weight to shorter codes. Algorithm: classic
    /// "Voorhis trick" — find the deepest length-limited symbol and
    /// promote it; find a shorter symbol and demote it; repeat until
    /// all lengths ≤ maxBits.
    private static func limitToMaxBits(_ lengths: [Int], maxBits: Int) -> [Int] {
        var L = lengths
        let n = L.count
        // Cap all at maxBits first.
        for i in 0..<n where L[i] > maxBits { L[i] = maxBits }
        // Compute Kraft sum (in units of 2^maxBits).
        var sum = 0
        for v in L where v > 0 { sum += 1 << (maxBits - v) }
        let target = 1 << maxBits
        // If sum < target, we under-subscribed (capping shorter codes).
        // Promote shortest non-zero entries to length 1 until sum reaches target.
        // If sum > target (shouldn't happen after capping), demote longest.
        while sum > target {
            // Find a symbol with maximum length < maxBits and demote it.
            var idx = -1
            for i in 0..<n where L[i] > 0 && L[i] < maxBits {
                if idx == -1 || L[i] > L[idx] { idx = i }
            }
            if idx == -1 { break }
            sum -= 1 << (maxBits - L[idx])
            L[idx] += 1
            sum += 1 << (maxBits - L[idx])
        }
        while sum < target {
            // Promote a symbol with min length toward shorter (smaller length).
            // Find a length-maxBits entry to promote, or shortest > 1.
            var idx = -1
            for i in 0..<n where L[i] > 1 {
                if idx == -1 || L[i] < L[idx] { idx = i }
            }
            if idx == -1 { break }
            sum -= 1 << (maxBits - L[idx])
            L[idx] -= 1
            sum += 1 << (maxBits - L[idx])
        }
        return L
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
        blCount[0] = 0

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
