// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes

/// LZ77 match-finder using a chained hash table.
///
/// Produces a stream of ``EncoderCommand`` values from the input bytes.
/// Quality affects search depth (chain pointers visited per hash bucket)
/// and max-distance window; everything else is constant.
///
/// Quality tiers:
/// - 0: literal-only (no matching).
/// - 1-3: depth 4, max distance 1 KiB.
/// - 4-6: depth 16, max distance 64 KiB.
/// - 7-11: depth 64, max distance 4 MiB (full LGWIN=22 window).
enum MatchFinder {
    private static let minMatch = 4
    private static let maxMatch = 16384
    private static let hashBits = 16
    private static let hashBuckets = 1 << hashBits

    static func scan(_ input: Bytes, quality: Brotli.Quality) -> [EncoderCommand] {
        let q = quality.rawValue
        let bytes = Array(input)
        if bytes.isEmpty { return [] }

        // Quality 0: literal-only path. One command, no copy.
        if q == 0 {
            return [EncoderCommand(insertLits: bytes, copyLen: 0, distance: 0)]
        }

        let (maxDist, maxChainDepth): (Int, Int) = {
            switch q {
            case 1...3: return (1024, 4)
            case 4...6: return (65_536, 16)
            case 7...11: return (4_194_304, 64)
            default: return (1024, 4)
            }
        }()

        // Linear chained hash.
        var head = [Int](repeating: -1, count: hashBuckets)
        var prev = [Int](repeating: -1, count: bytes.count)

        var commands: [EncoderCommand] = []
        var pendingLits: [UInt8] = []
        var i = 0

        while i < bytes.count {
            // Need at least minMatch bytes for a possible match.
            if i + minMatch > bytes.count {
                // Tail of stream — remaining bytes as literals.
                pendingLits.append(contentsOf: bytes[i..<bytes.count])
                i = bytes.count
                break
            }

            let h = hashAt(bytes, pos: i)

            // Walk the chain for the best match.
            var bestLen = 0
            var bestDist = 0
            var chainPos = head[h]
            var depth = 0
            while chainPos != -1 && depth < maxChainDepth {
                let dist = i - chainPos
                if dist > maxDist { break }
                // Compare bytes from chainPos vs i.
                var len = 0
                let maxPossible = min(maxMatch, bytes.count - i)
                while len < maxPossible && bytes[chainPos + len] == bytes[i + len] {
                    len += 1
                }
                if len >= minMatch && len > bestLen {
                    bestLen = len
                    bestDist = dist
                    if len >= maxMatch { break }
                }
                chainPos = prev[chainPos]
                depth += 1
            }

            // Update chain with current position.
            prev[i] = head[h]
            head[h] = i

            if bestLen >= minMatch {
                commands.append(EncoderCommand(
                    insertLits: pendingLits,
                    copyLen: bestLen,
                    distance: bestDist
                ))
                pendingLits = []
                // Advance past the match. We skip inserting hash entries for
                // positions inside the match (positions 1..bestLen-1); costs
                // compression ratio but simplifies bookkeeping for v0.2.
                i += bestLen
            } else {
                pendingLits.append(bytes[i])
                i += 1
            }
        }

        // Flush trailing literals as a final command with copyLen=0.
        if !pendingLits.isEmpty {
            commands.append(EncoderCommand(
                insertLits: pendingLits, copyLen: 0, distance: 0
            ))
        }

        return commands
    }

    /// 16-bit hash of 4 bytes at `pos`. Multiplicative mix.
    private static func hashAt(_ bytes: [UInt8], pos: Int) -> Int {
        let b0 = UInt32(bytes[pos])
        let b1 = UInt32(bytes[pos + 1])
        let b2 = UInt32(bytes[pos + 2])
        let b3 = UInt32(bytes[pos + 3])
        let word = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        let mixed = word &* 0x9E3779B1
        return Int(mixed >> (32 - hashBits)) & (hashBuckets - 1)
    }
}
