// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// RFC 7932 § 4 distance decoder.
///
/// Distance alphabet size = `16 + NDIRECT + (48 << NPOSTFIX)`.
/// - Symbols 0..15 reference a last-distance ring buffer + small offsets
///   per § 4 (ring-buffer references; no extra bits).
/// - Symbols 16..15+NDIRECT are direct distance encodings (no extra bits).
/// - Symbols ≥ 16+NDIRECT use the postfix-suffix formula in § 4 with
///   `1..24` extra bits.
///
/// The ring buffer of the four last distances is initialized to
/// `[16, 15, 11, 4]` per § 4 (at *stream* start, not per meta-block).
/// Symbol 0 references the most-recent distance but does NOT push.
/// All other ring/direct/postfix paths DO push the resolved distance,
/// EXCEPT static-dictionary references (handled by the caller).
struct DistanceDecoder {
    let ndirect: Int
    let npostfix: Int

    /// Last-distance ring buffer. `ringBuffer[(ringPos - 1) & 3]` is the
    /// most-recent distance; `(ringPos - 4) & 3` (= `ringPos & 3`) is
    /// the fourth-most-recent.
    var ringBuffer: [Int] = [16, 15, 11, 4]
    var ringPos: Int = 0

    init(ndirect: Int, npostfix: Int) {
        self.ndirect = ndirect
        self.npostfix = npostfix
    }

    /// Decode a distance from `symbol` (already read from the distance-
    /// alphabet prefix code). May consume `ndistbits` extra bits from
    /// `r` for the postfix path. Updates the ring buffer for all paths
    /// except symbol 0 (which references the most-recent without push).
    mutating func decode(symbol: Int, _ r: inout BitReader) throws(BrotliError) -> Int {
        if symbol < 16 {
            return try resolveRingSymbol(symbol)
        }
        if symbol - 16 < ndirect {
            let distance = symbol - 15  // direct: symbol 16 → 1, 17 → 2, ...
            push(distance)
            return distance
        }
        // Postfix-suffix path.
        let base = symbol - ndirect - 16
        let postfixMask = (1 << npostfix) - 1
        let hcode = base >> npostfix
        let lcode = base & postfixMask
        let ndistbits = 1 + (base >> (npostfix + 1))
        guard ndistbits <= 24 else { throw .invalidDistance }
        let extra = ndistbits == 0 ? 0 : Int(try r.readBits(ndistbits))
        let offset = ((2 + (hcode & 1)) << ndistbits) - 4
        let distance = ((offset + extra) << npostfix) + lcode + ndirect + 1
        guard distance > 0 else { throw .invalidDistance }
        push(distance)
        return distance
    }

    /// § 4 small-distance symbols 0..15. Returns the resolved distance.
    /// Symbol 0 does NOT push to the ring; symbols 1..15 DO push.
    private mutating func resolveRingSymbol(_ symbol: Int) throws(BrotliError) -> Int {
        switch symbol {
        case 0:
            // Last distance — no push.
            return ringBuffer[(ringPos - 1) & 3]
        case 1:
            let d = ringBuffer[(ringPos - 2) & 3]
            push(d); return d
        case 2:
            let d = ringBuffer[(ringPos - 3) & 3]
            push(d); return d
        case 3:
            let d = ringBuffer[(ringPos - 4) & 3]
            push(d); return d
        case 4...9:
            // last ± k where k = (symbol - 2) >> 1, sign = (symbol - 4) & 1 ? +1 : -1
            let last = ringBuffer[(ringPos - 1) & 3]
            let k = (symbol - 2) >> 1
            let sign = (symbol & 1) == 0 ? -1 : 1   // 4 → -1, 5 → +1, 6 → -1, ...
            let d = last + sign * k
            guard d > 0 else { throw .invalidDistance }
            push(d); return d
        case 10...15:
            // second-to-last ± k pattern
            let second = ringBuffer[(ringPos - 2) & 3]
            let k = (symbol - 8) >> 1
            let sign = (symbol & 1) == 0 ? -1 : 1   // 10 → -1, 11 → +1, ...
            let d = second + sign * k
            guard d > 0 else { throw .invalidDistance }
            push(d); return d
        default:
            throw .invalidDistance
        }
    }

    /// Push a new distance into the ring buffer (overwriting the
    /// fourth-most-recent entry).
    mutating func push(_ distance: Int) {
        ringBuffer[ringPos & 3] = distance
        ringPos = (ringPos + 1) & 3
    }
}
