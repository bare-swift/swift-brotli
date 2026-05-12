// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// RFC 7932 § 4 distance decoder.
///
/// Distance alphabet size = `16 + NDIRECT + (48 << NPOSTFIX)`.
/// - Symbols 0..15 reference a last-distance ring buffer (§ 4 Table 1).
/// - Symbols 16..15+NDIRECT are direct distance encodings.
/// - Symbols ≥ 16+NDIRECT use the postfix-suffix formula in § 4.
///
/// The decoder maintains a 4-entry last-distance ring buffer initialized
/// to `[16, 15, 11, 4]` per § 9.2 and updated on every non-ring decode.
///
/// **Stage B handoff.** Scaffold in place; the algorithm body fills in
/// during Stage B. The ring-buffer initialization and update *rules*
/// are documented inline so the executor can verify against § 4.
struct DistanceDecoder {
    let ndirect: Int
    let npostfix: Int

    /// Last-distance ring buffer (§ 4). Indices 0..3 correspond to
    /// "most recent" through "fourth most recent" non-ring distance.
    var ringBuffer: [Int] = [16, 15, 11, 4]

    /// Next write position in `ringBuffer` (mod 4).
    var ringPos: Int = 0

    init(ndirect: Int, npostfix: Int) {
        self.ndirect = ndirect
        self.npostfix = npostfix
    }

    /// Decode a distance from `symbol` (already read from the distance-
    /// alphabet prefix code) and `distContext` (from the insert-and-copy
    /// decode, value 0..3 per § 5). May consume additional bits from `r`
    /// for the postfix/extra-bits path.
    ///
    /// **Stage B:** implement per § 4. Logic outline:
    ///
    ///   if symbol < 16:
    ///       // Small-distance ring-buffer reference. § 4 Table 1 maps
    ///       // (symbol, distContext) → (ringIndex, adjustment).
    ///       // Result = ringBuffer[ringPos - 1 - ringIndex] + adjustment.
    ///       // Some adjustments depend on copyLen (specifically the
    ///       // "copy-length-2" special case for symbol 9..15 — see § 4).
    ///       // Do NOT update the ring buffer.
    ///       return result
    ///
    ///   if symbol - 16 < ndirect:
    ///       distance = symbol - 15
    ///       updateRing(distance)
    ///       return distance
    ///
    ///   // Postfix-suffix path (§ 4):
    ///   let ndistbits = 1 + ((symbol - ndirect - 16) >> (npostfix + 1))
    ///   let hcode = (symbol - ndirect - 16) >> npostfix
    ///   let lcode = (symbol - ndirect - 16) & ((1 << npostfix) - 1)
    ///   let offset = ((2 + (hcode & 1)) << ndistbits) - 4
    ///   let extra = readBits(ndistbits)
    ///   let distance = ((offset + extra) << npostfix) | lcode + ndirect + 1
    ///   updateRing(distance)
    ///   return distance
    mutating func decode(
        symbol: Int,
        distContext: Int,
        copyLen: Int,
        _ r: inout BitReader
    ) throws(BrotliError) -> Int {
        // Stage B: implement per RFC 7932 § 4 (algorithm sketched above).
        fatalError("DistanceDecoder.decode — implement in Stage B per RFC 7932 § 4")
    }

    /// Push a new distance into the ring buffer, replacing the
    /// fourth-most-recent entry.
    mutating func updateRing(_ distance: Int) {
        ringBuffer[ringPos & 3] = distance
        ringPos = (ringPos + 1) & 3
    }
}
