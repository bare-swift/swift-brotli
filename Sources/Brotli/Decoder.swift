// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes

/// Top-level brotli decode driver per RFC 7932 § 9.
enum Decoder {
    static func decode(_ bytes: Bytes, outputCap: Int) throws(BrotliError) -> Bytes {
        var reader = BitReader(bytes)
        let wbits = try StreamHeader.readWBITS(&reader)
        let windowSize = (1 << wbits) - 16
        var output = OutputBuffer(cap: outputCap)
        // The distance ring buffer is persistent across meta-blocks per § 4.
        // We re-initialize ndirect/npostfix per-meta-block but preserve the ring.
        var distance = DistanceDecoder(ndirect: 0, npostfix: 0)

        while true {
            let header = try MetaBlockHeader.read(&reader)
            if header.isLastEmpty { break }
            if header.mlen == 0 {
                if header.isLast { break }
                continue
            }
            if header.isUncompressed {
                reader.alignToByte()
                let literals = try reader.readBytes(header.mlen)
                try output.appendLiterals(literals)
                if header.isLast { break }
                continue
            }
            try decodeCompressedMetaBlock(
                mlen: header.mlen,
                windowSize: windowSize,
                reader: &reader,
                output: &output,
                distance: &distance
            )
            if header.isLast { break }
        }
        return output.toBytes()
    }

    /// § 9.2 meta-block prefix reader + § 9.3 decode loop.
    private static func decodeCompressedMetaBlock(
        mlen: Int,
        windowSize: Int,
        reader: inout BitReader,
        output: inout OutputBuffer,
        distance: inout DistanceDecoder
    ) throws(BrotliError) {
        // 1. Three BlockSwitchers (L, I, D).
        var lBlock = try BlockSwitcher.read(&reader)
        var iBlock = try BlockSwitcher.read(&reader)
        var dBlock = try BlockSwitcher.read(&reader)

        // 2. NPOSTFIX + NDIRECT.
        let npostfix = Int(try reader.readBits(2))
        let ndirectHigh = Int(try reader.readBits(4))
        let ndirect = ndirectHigh << npostfix
        // Preserve the ring buffer across re-construction.
        let savedRing = distance.ringBuffer
        let savedRingPos = distance.ringPos
        distance = DistanceDecoder(ndirect: ndirect, npostfix: npostfix)
        distance.ringBuffer = savedRing
        distance.ringPos = savedRingPos

        // 3. Context modes per literal block type (NBLTYPESL * 2 bits).
        var literalContextModes: [ContextMode] = []
        literalContextModes.reserveCapacity(lBlock.nblTypes)
        for _ in 0..<lBlock.nblTypes {
            let cmode = Int(try reader.readBits(2))
            guard let m = ContextMode(rawValue: UInt8(cmode)) else {
                throw .invalidContextMode
            }
            literalContextModes.append(m)
        }

        // 4. NTREESL + literal context map.
        let ntreesl = try BlockSwitcher.readVariableLengthCount(&reader)
        let litContextMap: [UInt8]
        if ntreesl > 1 {
            litContextMap = try ContextMap.readContextMap(
                &reader, size: 64 * lBlock.nblTypes, ntrees: ntreesl
            )
        } else {
            litContextMap = [UInt8](repeating: 0, count: 64 * lBlock.nblTypes)
        }

        // 5. NTREESD + distance context map.
        let ntreesd = try BlockSwitcher.readVariableLengthCount(&reader)
        let distContextMap: [UInt8]
        if ntreesd > 1 {
            distContextMap = try ContextMap.readContextMap(
                &reader, size: 4 * dBlock.nblTypes, ntrees: ntreesd
            )
        } else {
            distContextMap = [UInt8](repeating: 0, count: 4 * dBlock.nblTypes)
        }

        // 6. NTREESL literal prefix codes.
        var literalTrees: [PrefixCode] = []
        literalTrees.reserveCapacity(ntreesl)
        for _ in 0..<ntreesl {
            literalTrees.append(try PrefixCode.read(&reader, alphabetSize: 256))
        }

        // 7. NBLTYPESI insert-and-copy prefix codes.
        var icTrees: [PrefixCode] = []
        icTrees.reserveCapacity(iBlock.nblTypes)
        for _ in 0..<iBlock.nblTypes {
            icTrees.append(try PrefixCode.read(&reader, alphabetSize: 704))
        }

        // 8. NTREESD distance prefix codes.
        let distAlphabetSize = 16 + ndirect + (48 << npostfix)
        var distanceTrees: [PrefixCode] = []
        distanceTrees.reserveCapacity(ntreesd)
        for _ in 0..<ntreesd {
            distanceTrees.append(try PrefixCode.read(&reader, alphabetSize: distAlphabetSize))
        }

        // 9. Decode payload per § 9.3.
        let startCount = output.count
        let targetCount = startCount + mlen
        while output.count < targetCount {
            // 9.1. Read IC symbol.
            let icSym = try icTrees[iBlock.currentType].readSymbol(&reader)
            try iBlock.advance(&reader)
            let (insertCode, copyCode, useDistance) = try InsertCopy.decompose(icSym)
            let insertLen: Int
            let iExtra = InsertCopy.insertExtra[insertCode]
            if iExtra > 0 {
                insertLen = InsertCopy.insertBase[insertCode] + Int(try reader.readBits(iExtra))
            } else {
                insertLen = InsertCopy.insertBase[insertCode]
            }
            let copyLen: Int
            let cExtra = InsertCopy.copyExtra[copyCode]
            if cExtra > 0 {
                copyLen = InsertCopy.copyBase[copyCode] + Int(try reader.readBits(cExtra))
            } else {
                copyLen = InsertCopy.copyBase[copyCode]
            }

            // 9.2. Emit `insertLen` literals.
            for _ in 0..<insertLen {
                if output.count >= targetCount { break }
                let (p1, p2) = output.lastTwo
                let mode = literalContextModes[lBlock.currentType]
                let ctxID = mode.contextID(p1: p1, p2: p2)
                let mapIdx = lBlock.currentType * 64 + ctxID
                guard mapIdx >= 0 && mapIdx < litContextMap.count else { throw .invalidHeader }
                let treeIdx = Int(litContextMap[mapIdx])
                guard treeIdx >= 0 && treeIdx < literalTrees.count else { throw .invalidHeader }
                let litSym = try literalTrees[treeIdx].readSymbol(&reader)
                guard litSym >= 0 && litSym < 256 else { throw .invalidPrefixCode }
                try output.appendLiteral(UInt8(litSym))
                try lBlock.advance(&reader)
            }
            if output.count >= targetCount { break }

            // 9.3. Read distance.
            let dist: Int
            if !useDistance {
                // Reuse most-recent, no push.
                dist = distance.ringBuffer[(distance.ringPos - 1) & 3]
            } else {
                let distCtx = min(copyCode, 3)
                let mapIdx = dBlock.currentType * 4 + distCtx
                guard mapIdx >= 0 && mapIdx < distContextMap.count else { throw .invalidHeader }
                let treeIdx = Int(distContextMap[mapIdx])
                guard treeIdx >= 0 && treeIdx < distanceTrees.count else { throw .invalidHeader }
                let distSym = try distanceTrees[treeIdx].readSymbol(&reader)
                try dBlock.advance(&reader)
                dist = try distance.decode(symbol: distSym, &reader)
            }
            guard dist > 0 else { throw .invalidDistance }

            // 9.4. Copy from window or static dictionary.
            let maxBackward = min(output.count, windowSize)
            if dist <= maxBackward {
                try output.copy(distance: dist, length: copyLen)
            } else {
                // Static-dictionary reference per § 8.
                guard copyLen >= 4 && copyLen <= 24 else {
                    throw .invalidDictionaryReference
                }
                let distFromDictBase = dist - maxBackward - 1
                let numWords = Dictionary.counts[copyLen]
                guard numWords > 0 else { throw .invalidDictionaryReference }
                let wordIdx = distFromDictBase % numWords
                let transformIdx = distFromDictBase / numWords
                guard transformIdx >= 0 && transformIdx < Transforms.table.count else {
                    throw .invalidDictionaryReference
                }
                try output.appendDictionaryWord(
                    length: copyLen, index: wordIdx, transform: transformIdx
                )
            }
        }

        if output.count - startCount > mlen {
            throw .invalidMetaBlockHeader
        }
        // Touch silenced-mutation parameters to avoid "never mutated" warnings.
        _ = literalTrees
        _ = icTrees
        _ = distanceTrees
    }
}
