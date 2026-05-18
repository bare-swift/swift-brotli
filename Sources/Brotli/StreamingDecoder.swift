// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes

/// State-machine brotli decode driver for streaming inflate (v0.6+).
///
/// Holds a growing `BitReader`, an output buffer, a persistent distance
/// ring, and a `Phase` capturing inter- and intra-metablock position.
/// ``feed(_:)`` appends compressed input; ``run()`` consumes as much as
/// possible, pausing cleanly when input is exhausted.
///
/// Snapshots are taken at well-defined atomic-read boundaries (before
/// each Huffman symbol read, each extra-bits read, each header bit
/// read). A `.truncated` throw inside a checkpointed scope rewinds the
/// reader to the snapshot so the next ``run()`` resumes from a clean
/// position. Per-symbol state (insertLen / copyLen / useDistance /
/// emitted-literal-count / distance) lives in the ``BodyState`` and
/// ``BodySubPhase`` so it survives `update(_:)` boundaries.
///
/// Adopters interact through ``Brotli/Streaming/Decoder``; this type
/// is package-internal.
struct StreamingDecoder: Sendable {
    /// Inter- and intra-metablock position.
    enum Phase: Sendable {
        /// Need to read WBITS at the top of the stream.
        case awaitingStreamHeader

        /// Stream header consumed; ready to start the next metablock
        /// header (or finish if BFINAL was on the previous metablock).
        case awaitingMetaBlockHeader

        /// In an uncompressed metablock; `remaining` payload bytes left
        /// to copy.
        case inUncompressed(mlen: Int, remaining: Int, isLast: Bool)

        /// Metablock header decoded as compressed; need to parse the
        /// trees + context maps before entering the body. This whole
        /// parse is bundled under a single snapshot — on truncation we
        /// rewind and re-parse next run().
        case awaitingMetaBlockTrees(mlen: Int, isLast: Bool)

        /// Inside a compressed metablock's body, at some sub-phase.
        case inMetaBlockBody(BodyState)

        /// Last metablock consumed; stream complete.
        case done
    }

    /// Substate within a compressed metablock body.
    ///
    /// Body steps in order:
    /// 1. Read insert-and-copy symbol + extra bits (`awaitIC`).
    /// 2. Emit `insertLen` literals one at a time (`emittingLiterals`).
    /// 3. Read distance symbol + extra (only if `useDistance`)
    ///    (`awaitDistance`).
    /// 4. Match-copy or dictionary-append (atomic; no reads).
    ///
    /// Each transition snapshots the reader before any read; on
    /// truncation, restore + return.
    enum BodySubPhase: Sendable {
        /// Ready to read the next IC symbol.
        case awaitIC

        /// IC decoded; literals being emitted. `emitted` counts the
        /// literals already appended to output during this iteration.
        case emittingLiterals(
            insertLen: Int,
            copyLen: Int,
            useDistance: Bool,
            emitted: Int)

        /// Literals done; needs a distance read (only used when
        /// `useDistance == true`).
        case awaitDistance(copyLen: Int)
    }

    /// Per-metablock state. All trees/context-maps live here so they
    /// survive `update(_:)` boundaries within a metablock.
    struct BodyState: Sendable {
        let mlen: Int
        let startCount: Int
        let isLast: Bool
        var lBlock: BlockSwitcher
        var iBlock: BlockSwitcher
        var dBlock: BlockSwitcher
        let literalContextModes: [ContextMode]
        let litContextMap: [UInt8]
        let distContextMap: [UInt8]
        var literalTrees: [PrefixCode]
        var icTrees: [PrefixCode]
        var distanceTrees: [PrefixCode]
        var distance: DistanceDecoder
        var subPhase: BodySubPhase
    }

    var reader: BitReader
    var output: OutputBuffer
    var phase: Phase
    /// Window size in bytes, computed from WBITS at stream header.
    /// Persists across metablocks.
    var windowSize: Int
    /// Persistent distance ring buffer across metablocks per § 4.
    /// Stored alongside output so we can ferry it into each BodyState.
    var carriedDistance: DistanceDecoder

    init(outputCap: Int = Brotli.defaultOutputCap) {
        self.reader = BitReader()
        self.output = OutputBuffer(cap: outputCap)
        self.phase = .awaitingStreamHeader
        self.windowSize = 0
        self.carriedDistance = DistanceDecoder(ndirect: 0, npostfix: 0)
    }

    /// Append new compressed bytes to the reader buffer.
    mutating func feed(_ chunk: ContiguousArray<UInt8>) {
        reader.append(chunk)
    }

    /// Run the state machine forward as far as the buffered input
    /// allows. Returns when either:
    /// - `phase == .done`: stream complete.
    /// - A `.truncated` was caught and the reader rewound: more input
    ///   needed.
    ///
    /// Throws any BrotliError other than `.truncated` directly. The
    /// caller (Streaming.Decoder) is responsible for surfacing errors
    /// at the right API boundary.
    mutating func run() throws(BrotliError) {
        loop: while true {
            switch phase {
            case .done:
                return

            case .awaitingStreamHeader:
                let snap = reader.snapshot()
                do {
                    let wbits = try StreamHeader.readWBITS(&reader)
                    windowSize = (1 << wbits) - 16
                    phase = .awaitingMetaBlockHeader
                } catch BrotliError.truncated {
                    reader.restore(snap)
                    return
                } catch let e as BrotliError {
                    throw e
                }

            case .awaitingMetaBlockHeader:
                let snap = reader.snapshot()
                do {
                    let header = try MetaBlockHeader.read(&reader)
                    if header.isLastEmpty {
                        phase = .done
                        continue loop
                    }
                    if header.mlen == 0 {
                        phase = header.isLast ? .done : .awaitingMetaBlockHeader
                        continue loop
                    }
                    if header.isUncompressed {
                        reader.alignToByte()
                        phase = .inUncompressed(
                            mlen: header.mlen,
                            remaining: header.mlen,
                            isLast: header.isLast)
                    } else {
                        phase = .awaitingMetaBlockTrees(
                            mlen: header.mlen,
                            isLast: header.isLast)
                    }
                } catch BrotliError.truncated {
                    reader.restore(snap)
                    return
                } catch let e as BrotliError {
                    throw e
                }

            case .inUncompressed(let mlen, var remaining, let isLast):
                if remaining == 0 {
                    phase = isLast ? .done : .awaitingMetaBlockHeader
                    continue loop
                }
                let avail = reader.availableBytesAligned()
                if avail == 0 {
                    phase = .inUncompressed(mlen: mlen, remaining: remaining, isLast: isLast)
                    return
                }
                let toCopy = Swift.min(remaining, avail)
                let snap = reader.snapshot()
                do {
                    let chunk = try reader.readBytes(toCopy)
                    try output.appendLiterals(chunk)
                    remaining -= toCopy
                    if remaining == 0 {
                        phase = isLast ? .done : .awaitingMetaBlockHeader
                    } else {
                        phase = .inUncompressed(
                            mlen: mlen, remaining: remaining, isLast: isLast)
                        return
                    }
                } catch BrotliError.truncated {
                    reader.restore(snap)
                    return
                } catch let e as BrotliError {
                    throw e
                }

            case .awaitingMetaBlockTrees(let mlen, let isLast):
                let snap = reader.snapshot()
                do {
                    let body = try parseMetaBlockTrees(mlen: mlen, isLast: isLast)
                    phase = .inMetaBlockBody(body)
                } catch BrotliError.truncated {
                    reader.restore(snap)
                    return
                } catch let e as BrotliError {
                    throw e
                }

            case .inMetaBlockBody(var body):
                let snap = reader.snapshot()
                let bodyComplete: Bool
                do {
                    bodyComplete = try advanceBody(&body)
                } catch BrotliError.truncated {
                    reader.restore(snap)
                    // Don't write `body` back — its mutations during the
                    // failed step are discarded along with the reader.
                    return
                } catch let e as BrotliError {
                    throw e
                }
                if bodyComplete {
                    if output.count - body.startCount > body.mlen {
                        throw BrotliError.invalidMetaBlockHeader
                    }
                    carriedDistance = body.distance
                    phase = body.isLast ? .done : .awaitingMetaBlockHeader
                } else {
                    phase = .inMetaBlockBody(body)
                }
            }
        }
    }

    // MARK: - Tree parsing

    /// Parse one compressed metablock's trees + context maps. Called
    /// under a single snapshot — on truncation, the caller rewinds and
    /// re-parses on the next run().
    private mutating func parseMetaBlockTrees(
        mlen: Int, isLast: Bool
    ) throws(BrotliError) -> BodyState {
        var lBlock = try BlockSwitcher.read(&reader)
        var iBlock = try BlockSwitcher.read(&reader)
        var dBlock = try BlockSwitcher.read(&reader)

        let npostfix = Int(try reader.readBits(2))
        let ndirectHigh = Int(try reader.readBits(4))
        let ndirect = ndirectHigh << npostfix
        var distance = DistanceDecoder(ndirect: ndirect, npostfix: npostfix)
        distance.ringBuffer = carriedDistance.ringBuffer
        distance.ringPos = carriedDistance.ringPos

        var literalContextModes: [ContextMode] = []
        literalContextModes.reserveCapacity(lBlock.nblTypes)
        for _ in 0..<lBlock.nblTypes {
            let cmode = Int(try reader.readBits(2))
            guard let m = ContextMode(rawValue: UInt8(cmode)) else {
                throw BrotliError.invalidContextMode
            }
            literalContextModes.append(m)
        }

        let ntreesl = try BlockSwitcher.readVariableLengthCount(&reader)
        let litContextMap: [UInt8]
        if ntreesl > 1 {
            litContextMap = try ContextMap.readContextMap(
                &reader, size: 64 * lBlock.nblTypes, ntrees: ntreesl)
        } else {
            litContextMap = [UInt8](repeating: 0, count: 64 * lBlock.nblTypes)
        }

        let ntreesd = try BlockSwitcher.readVariableLengthCount(&reader)
        let distContextMap: [UInt8]
        if ntreesd > 1 {
            distContextMap = try ContextMap.readContextMap(
                &reader, size: 4 * dBlock.nblTypes, ntrees: ntreesd)
        } else {
            distContextMap = [UInt8](repeating: 0, count: 4 * dBlock.nblTypes)
        }

        var literalTrees: [PrefixCode] = []
        literalTrees.reserveCapacity(ntreesl)
        for _ in 0..<ntreesl {
            literalTrees.append(try PrefixCode.read(&reader, alphabetSize: 256))
        }

        var icTrees: [PrefixCode] = []
        icTrees.reserveCapacity(iBlock.nblTypes)
        for _ in 0..<iBlock.nblTypes {
            icTrees.append(try PrefixCode.read(&reader, alphabetSize: 704))
        }

        let distAlphabetSize = 16 + ndirect + (48 << npostfix)
        var distanceTrees: [PrefixCode] = []
        distanceTrees.reserveCapacity(ntreesd)
        for _ in 0..<ntreesd {
            distanceTrees.append(try PrefixCode.read(&reader, alphabetSize: distAlphabetSize))
        }

        // Silence "never mutated" warnings on locals that are intentionally
        // var because the existing one-shot Decoder pattern mutates them
        // during reads above.
        _ = lBlock
        _ = iBlock
        _ = dBlock

        return BodyState(
            mlen: mlen,
            startCount: output.count,
            isLast: isLast,
            lBlock: lBlock,
            iBlock: iBlock,
            dBlock: dBlock,
            literalContextModes: literalContextModes,
            litContextMap: litContextMap,
            distContextMap: distContextMap,
            literalTrees: literalTrees,
            icTrees: icTrees,
            distanceTrees: distanceTrees,
            distance: distance,
            subPhase: .awaitIC
        )
    }

    // MARK: - Body advancement

    /// Advance the metablock body by one atomic step. Returns `true`
    /// when the metablock body is complete (output reached targetCount
    /// or block-switching exhausted). Throws `.truncated` if a read
    /// can't complete; caller is responsible for snapshotting/restoring
    /// the reader.
    private mutating func advanceBody(
        _ body: inout BodyState
    ) throws(BrotliError) -> Bool {
        let targetCount = body.startCount + body.mlen
        if output.count >= targetCount {
            return true
        }

        switch body.subPhase {
        case .awaitIC:
            let icSym = try body.icTrees[body.iBlock.currentType].readSymbol(&reader)
            try body.iBlock.advance(&reader)
            let (insertCode, copyCode, useDistance) = try InsertCopy.decompose(icSym)
            let insertLen: Int
            let iExtra = InsertCopy.insertExtra[insertCode]
            if iExtra > 0 {
                insertLen = InsertCopy.insertBase[insertCode] + Int(try reader.readBits(iExtra))
            } else {
                insertLen = InsertCopy.insertBase[insertCode]
            }
            let copyLenForDecode: Int
            let cExtra = InsertCopy.copyExtra[copyCode]
            if cExtra > 0 {
                copyLenForDecode = InsertCopy.copyBase[copyCode] + Int(try reader.readBits(cExtra))
            } else {
                copyLenForDecode = InsertCopy.copyBase[copyCode]
            }
            // Stash copyCode in the high bits of useDistance? No — we need
            // copyCode for the distance-context decision later. Encode it
            // in the BodySubPhase by re-deriving from icSym on retry?
            // Cleaner: don't lose copyCode. Store it alongside copyLen.
            // We pack (copyCode, copyLen) into a single Int: copyCode
            // is 0..23, copyLen fits in a positive Int. Use a tuple.
            // BodySubPhase.emittingLiterals takes copyLen + copyCode +
            // useDistance + emitted. Update the enum.
            body.subPhase = .emittingLiterals(
                insertLen: insertLen,
                copyLen: encodeCopyLenAndCode(copyLen: copyLenForDecode, copyCode: copyCode),
                useDistance: useDistance,
                emitted: 0)
            return false

        case .emittingLiterals(let insertLen, let packed, let useDistance, var emitted):
            let (copyLen, copyCode) = decodeCopyLenAndCode(packed)
            if emitted >= insertLen || output.count >= targetCount {
                // Literals done; transition to distance or copy.
                if output.count >= targetCount {
                    body.subPhase = .awaitIC
                    return output.count >= targetCount
                }
                if useDistance {
                    body.subPhase = .awaitDistance(copyLen: packed)
                    return false
                }
                // Use cached distance from ring.
                let dist = body.distance.ringBuffer[(body.distance.ringPos - 1) & 3]
                try performCopy(&body, dist: dist, copyLen: copyLen)
                body.subPhase = .awaitIC
                return output.count >= targetCount
            }
            // Emit one more literal.
            let (p1, p2) = output.lastTwo
            let mode = body.literalContextModes[body.lBlock.currentType]
            let ctxID = mode.contextID(p1: p1, p2: p2)
            let mapIdx = body.lBlock.currentType * 64 + ctxID
            guard mapIdx >= 0 && mapIdx < body.litContextMap.count else {
                throw BrotliError.invalidHeader
            }
            let treeIdx = Int(body.litContextMap[mapIdx])
            guard treeIdx >= 0 && treeIdx < body.literalTrees.count else {
                throw BrotliError.invalidHeader
            }
            let litSym = try body.literalTrees[treeIdx].readSymbol(&reader)
            guard litSym >= 0 && litSym < 256 else {
                throw BrotliError.invalidPrefixCode
            }
            try output.appendLiteral(UInt8(litSym))
            try body.lBlock.advance(&reader)
            emitted += 1
            body.subPhase = .emittingLiterals(
                insertLen: insertLen,
                copyLen: packed,
                useDistance: useDistance,
                emitted: emitted)
            // Suppress unused-variable warning on copyCode (used only
            // when transitioning out of emittingLiterals via distance
            // context calculation).
            _ = copyCode
            return false

        case .awaitDistance(let packed):
            let (copyLen, copyCode) = decodeCopyLenAndCode(packed)
            let distCtx = min(copyCode, 3)
            let mapIdx = body.dBlock.currentType * 4 + distCtx
            guard mapIdx >= 0 && mapIdx < body.distContextMap.count else {
                throw BrotliError.invalidHeader
            }
            let treeIdx = Int(body.distContextMap[mapIdx])
            guard treeIdx >= 0 && treeIdx < body.distanceTrees.count else {
                throw BrotliError.invalidHeader
            }
            let distSym = try body.distanceTrees[treeIdx].readSymbol(&reader)
            try body.dBlock.advance(&reader)
            let dist = try body.distance.decode(symbol: distSym, &reader)
            guard dist > 0 else { throw BrotliError.invalidDistance }
            try performCopy(&body, dist: dist, copyLen: copyLen)
            body.subPhase = .awaitIC
            return output.count >= targetCount
        }
    }

    /// Atomic match-copy or dictionary-append (no reader access).
    private mutating func performCopy(
        _ body: inout BodyState, dist: Int, copyLen: Int
    ) throws(BrotliError) {
        let maxBackward = min(output.count, windowSize)
        if dist <= maxBackward {
            try output.copy(distance: dist, length: copyLen)
        } else {
            guard copyLen >= 4 && copyLen <= 24 else {
                throw BrotliError.invalidDictionaryReference
            }
            let distFromDictBase = dist - maxBackward - 1
            let numWords = Dictionary.counts[copyLen]
            guard numWords > 0 else { throw BrotliError.invalidDictionaryReference }
            let wordIdx = distFromDictBase % numWords
            let transformIdx = distFromDictBase / numWords
            guard transformIdx >= 0 && transformIdx < Transforms.table.count else {
                throw BrotliError.invalidDictionaryReference
            }
            try output.appendDictionaryWord(
                length: copyLen, index: wordIdx, transform: transformIdx)
        }
    }

    // MARK: - Pack (copyLen, copyCode) into one Int
    //
    // The body sub-phase needs to remember `copyLen` (the actual copy
    // length in bytes; can be up to several MiB for large distances)
    // AND `copyCode` (0..23 per § 5; used to derive the distance
    // context). Two separate Ints would balloon the enum payload. Pack
    // both into one Int: low 6 bits = copyCode (0..23 fits in 5; pad
    // to 6 for safety), high bits = copyLen. copyLen fits in
    // (Int.bitWidth - 6) ≈ 58 bits — orders of magnitude larger than
    // any realistic value.

    @inline(__always)
    private func encodeCopyLenAndCode(copyLen: Int, copyCode: Int) -> Int {
        return (copyLen << 6) | (copyCode & 0x3F)
    }

    @inline(__always)
    private func decodeCopyLenAndCode(_ packed: Int) -> (Int, Int) {
        return (packed >> 6, packed & 0x3F)
    }
}

