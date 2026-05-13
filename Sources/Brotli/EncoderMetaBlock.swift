// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// Emits one brotli metablock (v0.2 always uses ONE per stream) into a
/// ``BitWriter`` per RFC 7932 § 9.2.
///
/// The stream-header (WBITS) is written by ``Encoder`` BEFORE this is
/// called; `emit` writes only the metablock itself.
///
/// v0.2 simplifications:
/// - ISLAST=1, ISLASTEMPTY iff `inputSize == 0`.
/// - NBLTYPES{L,I,D} = 1 (no block switching).
/// - NPOSTFIX=0, NDIRECT=0.
/// - CMODE[0] = 0 (UTF8 / signed literal context — but we don't use the
///   context map since NTREESL=1).
/// - NTREES{L,D} = 1 (single tree of each kind across the metablock).
/// - No literal / distance context maps emitted (single-tree case).
enum EncoderMetaBlock {
    static func emit(commands: [EncoderCommand], inputSize: Int, to w: inout BitWriter) {
        // ISLAST = 1
        w.writeBit(1)

        // Empty stream → ISLASTEMPTY = 1, then DONE.
        if inputSize == 0 {
            w.writeBit(1)
            return
        }
        w.writeBit(0)  // ISLASTEMPTY = 0

        // Pick MNIBBLES based on input size. Per § 9.2:
        //   MNIBBLES = 4 (16-bit MLEN-1) for inputSize ≤ 65536
        //   MNIBBLES = 5 (20-bit MLEN-1) for inputSize ≤ 1048576
        //   MNIBBLES = 6 (24-bit MLEN-1) for inputSize ≤ 16777216
        // Reader enforces: high nibble of MLEN-1 must be non-zero for
        // MNIBBLES > 4 (i.e., we must use the shortest viable encoding).
        let mlenMinus1 = inputSize - 1
        let mnibbles: Int
        let mnibblesCode: UInt32
        if inputSize <= 65536 {
            mnibbles = 4; mnibblesCode = 0
        } else if inputSize <= 1048576 {
            mnibbles = 5; mnibblesCode = 1
        } else {
            mnibbles = 6; mnibblesCode = 2
        }
        w.writeBits(mnibblesCode, count: 2)
        w.writeBits(UInt32(mlenMinus1), count: 4 * mnibbles)

        // ISUNCOMPRESSED is read by the decoder ONLY when !isLast. Since
        // we always set isLast=1, we don't emit this bit.

        // NBLTYPESL = 1 → variable-length count "0" (single bit).
        w.writeBit(0)
        // NBLTYPESI = 1
        w.writeBit(0)
        // NBLTYPESD = 1
        w.writeBit(0)

        // NPOSTFIX = 0 (2 bits)
        w.writeBits(0, count: 2)
        // NDIRECT (4 bits, then shifted by NPOSTFIX in the reader)
        w.writeBits(0, count: 4)

        // CMODE for each literal block type — we have 1, so emit 1 × 2 bits = 0.
        w.writeBits(0, count: 2)

        // NTREESL = 1 → single 0 bit.
        w.writeBit(0)
        // (NTREESL=1 → no context map.)

        // NTREESD = 1 → single 0 bit.
        w.writeBit(0)
        // (NTREESD=1 → no context map.)

        // Collect frequencies for the three trees.
        var litFreqs = [Int](repeating: 0, count: 256)
        var icFreqs = [Int](repeating: 0, count: 704)
        // Distance alphabet size with NPOSTFIX=0, NDIRECT=0 is 16 + 48 = 64.
        var distFreqs = [Int](repeating: 0, count: 64)

        for cmd in commands {
            for lit in cmd.insertLits { litFreqs[Int(lit)] += 1 }
            // Pick IC code:
            //   - if cmd.copyLen > 0: real (insertCode, copyCode) for those lengths.
            //   - if cmd.copyLen == 0 (last-literal-only): synthesize copyCode = 0
            //     (copy = 2). Decoder will break after literals exhaust MLEN.
            let insBr = EncoderCommandCoding.insertLengthCode(cmd.insertLits.count)
            let cpyBr: (code: Int, extra: UInt32, extraBits: Int)
            if cmd.copyLen >= 2 {
                cpyBr = EncoderCommandCoding.copyLengthCode(cmd.copyLen)
            } else {
                cpyBr = (code: 0, extra: 0, extraBits: 0)
            }
            let icSym = EncoderCommandCoding.combinedSymbol(
                insertCode: insBr.code, copyCode: cpyBr.code, useDistance: true
            )
            icFreqs[icSym] += 1
            if cmd.copyLen >= 2 {
                let dBr = EncoderCommandCoding.distanceCode(cmd.distance)
                distFreqs[dBr.code] += 1
            }
        }

        // Build the three trees.
        var litLengths = HuffmanBuilder.build(frequencies: litFreqs, maxBits: 15)
        var icLengths = HuffmanBuilder.build(frequencies: icFreqs, maxBits: 15)
        var distLengths = HuffmanBuilder.build(frequencies: distFreqs, maxBits: 15)

        // Complex-form prefix codes need a meta-Huffman with ≥ 2 used
        // symbols (the 18 length-codes 0..17), otherwise the meta-Kraft
        // sum can't reach 32 and the decoder rejects with FORMAT_CL_SPACE.
        // When an alphabet's lengths are uniform (every used symbol has
        // the same length value), the meta-Huffman has only 1 used symbol.
        // Perturb to introduce length variety so the meta-Huffman is valid.
        litLengths = ensureLengthVariety(litLengths)
        icLengths = ensureLengthVariety(icLengths)
        distLengths = ensureLengthVariety(distLengths)

        // Encoder-internal sanity: each tree's Kraft sum must equal 2^15.
        precondition(checkKraft(litLengths), "literal tree Kraft sum violation")
        precondition(checkKraft(icLengths), "ic tree Kraft sum violation")
        precondition(checkKraft(distLengths), "distance tree Kraft sum violation")

        // Emit prefix-code descriptors.
        PrefixCodeEmitter.emit(codeLengths: litLengths, alphabetSize: 256, to: &w)
        PrefixCodeEmitter.emit(codeLengths: icLengths, alphabetSize: 704, to: &w)
        PrefixCodeEmitter.emit(codeLengths: distLengths, alphabetSize: 64, to: &w)

        // Canonical codes for emit.
        let litCodes = HuffmanBuilder.canonicalCodes(from: litLengths)
        let icCodes = HuffmanBuilder.canonicalCodes(from: icLengths)
        let distCodes = HuffmanBuilder.canonicalCodes(from: distLengths)

        // The decoder's `readSimple` NSYM=1 path returns the single symbol
        // WITHOUT reading any bits (singleSymbol shortcut). When a tree has
        // exactly one used symbol, the encoder must emit 0 bits per
        // occurrence to match — even though canonical Huffman would
        // ordinarily assign length 1.
        let litSingle = litLengths.lazy.filter { $0 > 0 }.count == 1
        let icSingle = icLengths.lazy.filter { $0 > 0 }.count == 1
        let distSingle = distLengths.lazy.filter { $0 > 0 }.count == 1

        // Command stream.
        for cmd in commands {
            // 1) IC code: emit the Huffman code for the combined symbol
            //    (skip when tree has only one used symbol — decoder reads 0 bits).
            let insBr = EncoderCommandCoding.insertLengthCode(cmd.insertLits.count)
            let cpyBr: (code: Int, extra: UInt32, extraBits: Int)
            if cmd.copyLen >= 2 {
                cpyBr = EncoderCommandCoding.copyLengthCode(cmd.copyLen)
            } else {
                cpyBr = (code: 0, extra: 0, extraBits: 0)
            }
            let icSym = EncoderCommandCoding.combinedSymbol(
                insertCode: insBr.code, copyCode: cpyBr.code, useDistance: true
            )
            if !icSingle {
                emitCode(value: icCodes[icSym], length: icLengths[icSym], to: &w)
            }

            // 2) IC extra bits: insert-extras FIRST, then copy-extras (per § 5).
            w.writeBits(insBr.extra, count: insBr.extraBits)
            w.writeBits(cpyBr.extra, count: cpyBr.extraBits)

            // 3) Emit literals via the lit tree.
            for lit in cmd.insertLits {
                if !litSingle {
                    emitCode(value: litCodes[Int(lit)], length: litLengths[Int(lit)], to: &w)
                }
            }

            // 4) Distance code + extras — only if this command has a real copy.
            //    For literal-only-trailing commands (copyLen=0), the decoder's
            //    inner loop breaks after literals (output >= target), so the
            //    distance is never read.
            if cmd.copyLen >= 2 {
                let dBr = EncoderCommandCoding.distanceCode(cmd.distance)
                if !distSingle {
                    emitCode(value: distCodes[dBr.code], length: distLengths[dBr.code], to: &w)
                }
                w.writeBits(dBr.extra, count: dBr.extraBits)
            }
        }
    }

    /// Emit a canonical Huffman code value as `length` bits. Canonical codes
    /// are stored MSB-first numerically; brotli's LSB-first wire format
    /// requires bit-reversal at emit time so the decoder's MSB-first
    /// accumulator reconstructs the canonical numeric value.
    private static func emitCode(value: UInt32, length: Int, to w: inout BitWriter) {
        if length == 0 { return }
        w.writeBits(PrefixCodeEmitter.reverseBits(value, count: length), count: length)
    }

    /// Verify Kraft equality: Σ 2^-L over non-zero lengths must equal 1
    /// (in 2^15 fixed-point: sum equals 2^15). Single-symbol trees are
    /// allowed (return true unconditionally since the decoder short-
    /// circuits them).
    private static func checkKraft(_ lengths: [Int]) -> Bool {
        let nonZero = lengths.lazy.filter { $0 > 0 }.count
        if nonZero <= 1 { return true }
        var sum = 0
        let M = 1 << 15
        for L in lengths where L > 0 {
            if L > 15 { return false }
            sum += M >> L
        }
        return sum == M
    }

    /// If `lengths` has all non-zero entries equal to the same value `L`
    /// (uniform Huffman), perturb to introduce at least 2 distinct length
    /// values while preserving Kraft equality. Required so the meta-
    /// Huffman over the 18 length-codes has ≥ 2 used symbols — otherwise
    /// the decoder rejects with FORMAT_CL_SPACE.
    ///
    /// Perturbation: pick 3 used symbols. Change one from L to L-1 (Kraft
    /// +1/2^L), and two from L to L+1 (Kraft -2/2^(L+1) = -1/2^L). Net
    /// Kraft change = 0. Works when L ≥ 1 and L+1 ≤ maxBits=15, and at
    /// least 3 symbols are used.
    ///
    /// Edge cases:
    /// - 0 or 1 used symbols → no complex form; return unchanged.
    /// - 2 used symbols (both length 1) → 2 distinct symbols, but same
    ///   length value (both 1) → uniform. Can't perturb to length 0 (means
    ///   unused) or maintain Kraft with 2 symbols. v0.2 emits these in
    ///   SIMPLE form (handled by PrefixCodeEmitter NSYM=2 path) — so we
    ///   shouldn't reach here with this case. Guard anyway.
    private static func ensureLengthVariety(_ lengths: [Int]) -> [Int] {
        let usedIndices = lengths.enumerated().compactMap { $0.element > 0 ? $0.offset : nil }
        if usedIndices.count < 3 { return lengths }
        // Check if all used symbols have the same length.
        let firstL = lengths[usedIndices[0]]
        let uniform = usedIndices.allSatisfy { lengths[$0] == firstL }
        if !uniform { return lengths }
        // Perturb: 1 down to L-1, 2 up to L+1. Need L >= 1 and L+1 <= 15.
        let L = firstL
        guard L >= 1 && L + 1 <= 15 else {
            // L=0 impossible (it's filtered out). L=15: can't go higher.
            // Fall through: try L-1 with 2 down + 1 up at L+2 maybe? For v0.2
            // simplicity, accept that L=15 uniform is uncommon and skip.
            return lengths
        }
        var out = lengths
        out[usedIndices[0]] = L - 1
        out[usedIndices[1]] = L + 1
        out[usedIndices[2]] = L + 1
        return out
    }
}
