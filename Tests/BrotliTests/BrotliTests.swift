// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

import Testing
import Bytes
@testable import Brotli

@Suite("Brotli.decode API surface")
struct BrotliAPISurfaceTests {
    @Test("BrotliError has the documented cases")
    func errorCases() {
        let e: BrotliError = .truncated
        switch e {
        case .truncated, .invalidHeader, .invalidPrefixCode, .invalidContextMode,
             .invalidBlockType, .invalidDistance, .invalidDictionaryReference,
             .invalidTransform, .invalidMetaBlockHeader, .outputTooLarge,
             .inputTooLarge, .qualityOutOfRange:
            #expect(true)
        }
    }

    @Test("decode of an empty input throws .truncated")
    func emptyInputTruncated() {
        #expect(throws: BrotliError.truncated) {
            try Brotli.decode(Bytes())
        }
    }
}

@Suite("BitReader")
struct BitReaderTests {
    @Test("reads single bits LSB-first")
    func singleBits() throws {
        var r = BitReader(Bytes([0b00000001]))
        #expect(try r.readBit() == 1)
        #expect(try r.readBit() == 0)
        #expect(try r.readBit() == 0)
        #expect(try r.readBit() == 0)
    }

    @Test("reads multi-bit values LSB-first")
    func multiBit() throws {
        var r = BitReader(Bytes([0xAB, 0xCD]))
        #expect(try r.readBits(4) == 0xB)
        #expect(try r.readBits(4) == 0xA)
        #expect(try r.readBits(8) == 0xCD)
    }

    @Test("throws .truncated on EOF")
    func truncatedEOF() {
        var r = BitReader(Bytes([0x01]))
        _ = try? r.readBits(8)
        #expect(throws: BrotliError.truncated) {
            _ = try r.readBits(1)
        }
    }

    @Test("alignToByte drops partial bits")
    func alignDropsPartial() throws {
        var r = BitReader(Bytes([0xFF, 0xAA]))
        _ = try r.readBits(3)
        r.alignToByte()
        let next = try r.readBits(8)
        #expect(next == 0xAA)
    }
}

@Suite("StreamHeader.WBITS")
struct StreamHeaderTests {
    @Test("first bit 0 → WBITS=16")
    func defaultWindow() throws {
        var r = BitReader(Bytes([0b00000000]))
        let wbits = try StreamHeader.readWBITS(&r)
        #expect(wbits == 16)
    }

    @Test("first bit 1, next 3 bits non-zero → 17 + value")
    func largeWindow() throws {
        // bit 0 = 1, bits 1..3 = 001 (LSB-first → value 1). byte = 0b0000_0011 = 0x03.
        var r = BitReader(Bytes([0x03]))
        let wbits = try StreamHeader.readWBITS(&r)
        #expect(wbits == 18)
    }

    @Test("reserved 1 000 000 throws .invalidHeader")
    func reserved() {
        // bit 0 = 1, bits 1..6 = 000_000. byte 0 = 0x01, byte 1 = 0x00.
        var r = BitReader(Bytes([0x01, 0x00]))
        #expect(throws: BrotliError.invalidHeader) {
            _ = try StreamHeader.readWBITS(&r)
        }
    }
}

@Suite("MetaBlockHeader")
struct MetaBlockHeaderTests {
    @Test("ISLAST=1, ISLASTEMPTY=1 → empty final meta-block")
    func lastEmpty() throws {
        // ISLAST=1 (bit 0=1), ISLASTEMPTY=1 (bit 1=1). byte = 0x03.
        var r = BitReader(Bytes([0x03]))
        let h = try MetaBlockHeader.read(&r)
        #expect(h.isLast == true)
        #expect(h.isLastEmpty == true)
        #expect(h.mlen == 0)
    }
}

@Suite("OutputBuffer")
struct OutputBufferTests {
    @Test("appendLiteral grows storage")
    func appendLiteral() throws {
        var b = OutputBuffer(cap: 1024)
        try b.appendLiteral(0x41)
        try b.appendLiteral(0x42)
        #expect(b.count == 2)
        #expect(b.toBytes().storage == [0x41, 0x42])
    }

    @Test("copy back-reference (no overlap)")
    func copyNoOverlap() throws {
        var b = OutputBuffer(cap: 1024)
        try b.appendLiterals([0x41, 0x42, 0x43, 0x44, 0x45])
        try b.copy(distance: 5, length: 3)
        #expect(b.toBytes().storage == [0x41, 0x42, 0x43, 0x44, 0x45, 0x41, 0x42, 0x43])
    }

    @Test("copy with overlap (RLE: length > distance)")
    func copyOverlap() throws {
        var b = OutputBuffer(cap: 1024)
        try b.appendLiteral(0x41)
        try b.copy(distance: 1, length: 4)  // duplicate the 'A' four more times
        #expect(b.toBytes().storage == [0x41, 0x41, 0x41, 0x41, 0x41])
    }

    @Test("output cap respected")
    func capRespected() throws {
        var b = OutputBuffer(cap: 3)
        try b.appendLiterals([0x41, 0x42, 0x43])
        #expect(throws: BrotliError.outputTooLarge) {
            try b.appendLiteral(0x44)
        }
    }

    @Test("invalid distance (zero or past start) throws")
    func invalidDistance() throws {
        var b = OutputBuffer(cap: 1024)
        try b.appendLiterals([0x41, 0x42])
        #expect(throws: BrotliError.invalidDistance) {
            try b.copy(distance: 0, length: 1)
        }
        #expect(throws: BrotliError.invalidDistance) {
            try b.copy(distance: 99, length: 1)
        }
    }

    @Test("lastTwo with various states")
    func lastTwo() throws {
        var b = OutputBuffer(cap: 1024)
        #expect(b.lastTwo == (0, 0))
        try b.appendLiteral(0x41)
        #expect(b.lastTwo == (0x41, 0))
        try b.appendLiteral(0x42)
        try b.appendLiteral(0x43)
        #expect(b.lastTwo == (0x43, 0x42))
    }
}

@Suite("Transforms")
struct TransformsTests {
    @Test("table has exactly 121 entries")
    func tableSize() {
        #expect(Transforms.table.count == 121)
    }

    @Test("prefixSuffix has exactly 50 entries")
    func psCount() {
        #expect(Transforms.prefixSuffix.count == 50)
    }

    @Test("transform 0 is identity, identity, identity (\"\", word, \"\")")
    func transform0() throws {
        let word: [UInt8] = [0x41, 0x42, 0x43]  // "ABC"
        let out = try Transforms.apply(0, to: word[...])
        // table[0] = (49, .identity, 49); prefixSuffix[49] is "" (empty).
        #expect(out == word)
    }

    @Test("transform 1 appends ' '")
    func transform1() throws {
        let word: [UInt8] = [0x41, 0x42]  // "AB"
        let out = try Transforms.apply(1, to: word[...])
        // table[1] = (49, .identity, 0); prefixSuffix[0] is " ".
        #expect(out == [0x41, 0x42, 0x20])
    }

    @Test("transform 2 wraps word with leading + trailing space")
    func transform2() throws {
        let word: [UInt8] = [0x66, 0x6F, 0x6F]  // "foo"
        let out = try Transforms.apply(2, to: word[...])
        // table[2] = (0, .identity, 0); prefixSuffix[0] is " ".
        #expect(out == [0x20, 0x66, 0x6F, 0x6F, 0x20])
    }

    @Test("uppercaseFirst on lowercase ASCII flips bit 5")
    func uppercaseFirstASCII() throws {
        let word: [UInt8] = [0x61, 0x62, 0x63]  // "abc"
        let out = try Transforms.apply(4, to: word[...])
        // table[4] = (49, .uppercaseFirst, 0); prefix "", suffix " ".
        #expect(out == [0x41, 0x62, 0x63, 0x20])  // "Abc "
    }

    @Test("uppercaseAll flips all ASCII a-z")
    func uppercaseAllASCII() throws {
        let word: [UInt8] = [0x68, 0x65, 0x6C, 0x6C, 0x6F]  // "hello"
        let out = try Transforms.apply(44, to: word[...])
        // table[44] = (49, .uppercaseAll, 49); prefix "", suffix "".
        #expect(out == [0x48, 0x45, 0x4C, 0x4C, 0x4F])  // "HELLO"
    }

    @Test("omitFirst1 drops first byte")
    func omitFirst1() throws {
        let word: [UInt8] = [0x41, 0x42, 0x43]
        let out = try Transforms.apply(3, to: word[...])
        // table[3] = (49, .omitFirst1, 49). Just drop first byte.
        #expect(out == [0x42, 0x43])
    }

    @Test("OutputBuffer.appendDictionaryWord wires through to Transforms")
    func appendDictionaryWord() throws {
        var b = OutputBuffer(cap: 1024)
        // Length-4 word at index 0, transform 0 (identity, no prefix/suffix).
        // Dictionary.bytes[0..4] is the first 4-byte word.
        try b.appendDictionaryWord(length: 4, index: 0, transform: 0)
        #expect(b.count == 4)
        // The bytes should match the first 4 bytes of the dictionary.
        let expected: [UInt8] = [
            Dictionary.bytes[0], Dictionary.bytes[1],
            Dictionary.bytes[2], Dictionary.bytes[3],
        ]
        #expect(Array(b.toBytes().storage) == expected)
    }
}

@Suite("ContextMap LUTs")
struct ContextMapLUTTests {
    @Test("all four LUT pairs are 256 entries each")
    func allLUTsCorrectSize() {
        #expect(ContextMap.lut0_lsb6.count == 256)
        #expect(ContextMap.lut1_lsb6.count == 256)
        #expect(ContextMap.lut0_msb6.count == 256)
        #expect(ContextMap.lut1_msb6.count == 256)
        #expect(ContextMap.lut0_utf8.count == 256)
        #expect(ContextMap.lut1_utf8.count == 256)
        #expect(ContextMap.lut0_signed.count == 256)
        #expect(ContextMap.lut1_signed.count == 256)
    }

    @Test("LSB6 mode returns low 6 bits of p1")
    func lsb6Mode() {
        let m: ContextMode = .lsb6
        #expect(m.contextID(p1: 0x00, p2: 0xFF) == 0)
        #expect(m.contextID(p1: 0x3F, p2: 0x00) == 0x3F)
        #expect(m.contextID(p1: 0xC1, p2: 0x77) == 0x01)
    }

    @Test("MSB6 mode returns high 6 bits of p1")
    func msb6Mode() {
        let m: ContextMode = .msb6
        #expect(m.contextID(p1: 0x00, p2: 0xFF) == 0)
        #expect(m.contextID(p1: 0xFC, p2: 0x00) == 0x3F)
        #expect(m.contextID(p1: 0x80, p2: 0xAA) == 0x20)
    }

    @Test("UTF8 mode on ASCII letter combines lut0 + lut1")
    func utf8Mode() {
        // 'a' (0x61) → lut0[0x61] = 56 (lower-case consonant slot); 'b' (0x62)
        // → lut1[0x62] = 3. Combined 56 | 3 = 59.
        let m: ContextMode = .utf8
        let ctx = m.contextID(p1: 0x61, p2: 0x62)
        #expect(ctx == 59)
    }
}

@Suite("PrefixCode")
struct PrefixCodeTests {
    @Test("RFC 7932 § 3.2 example: lengths (2, 1, 3, 3) → codes 10, 0, 110, 111")
    func canonicalExample() throws {
        let pc = try PrefixCode(lengths: [2, 1, 3, 3], maxBits: 4)
        // From spec: A=10, B=0, C=110, D=111.
        // Stream order (LSB-first): A reads "0, 1", B reads "0", C reads "0, 1, 1",
        // D reads "1, 1, 1" — wait that's wrong. Re-derive:
        //   A=10 MSB-first; stream emits MSB first → bits "1, 0" in stream order
        //   B=0 → stream emits "0"
        //   C=110 → stream emits "1, 1, 0"
        //   D=111 → stream emits "1, 1, 1"
        // The bit reader returns LSB-first integers, but our decoder reads
        // one bit at a time and builds an MSB-first accumulator (correct).
        //
        // For A=10: read bit 1, build acc=1 (L=1, codeStart[1]=0, codeEnd[1]=1
        // so no match). Read bit 0, build acc=10=2 (L=2, codeStart[2]=2,
        // codeEnd[2]=3 → match, offset 0). symbolStart[2] should point to
        // symbol A (index 0).
        //
        // Construct a stream that emits A, B, C, D in succession:
        //   A → "1, 0"
        //   B → "0"
        //   C → "1, 1, 0"
        //   D → "1, 1, 1"
        // Concatenated bits (LSB-first packing into bytes):
        //   bit 0 = 1 (A's MSB)
        //   bit 1 = 0 (A's LSB)
        //   bit 2 = 0 (B's only)
        //   bit 3 = 1 (C's MSB)
        //   bit 4 = 1 (C's mid)
        //   bit 5 = 0 (C's LSB)
        //   bit 6 = 1 (D's MSB)
        //   bit 7 = 1 (D's mid)
        //   (byte 1) bit 0 = 1 (D's LSB)
        // byte 0 = 0b1101_1001 = 0xD9; byte 1 = 0b0000_0001 = 0x01.
        var r = BitReader(Bytes([0xD9, 0x01]))
        var pc2 = pc
        #expect(try pc2.readSymbol(&r) == 0)  // A
        #expect(try pc2.readSymbol(&r) == 1)  // B
        #expect(try pc2.readSymbol(&r) == 2)  // C
        #expect(try pc2.readSymbol(&r) == 3)  // D
    }

    @Test("single-symbol alphabet shortcuts (zero bits read)")
    func singleSymbol() throws {
        // alphabet size 4, only symbol 2 has length 0 (or len 1 per
        // single-symbol shortcut path). readSymbol returns 2 without bits.
        let pc = try PrefixCode.makeSingleSymbol(2, alphabetSize: 4, maxBits: 15)
        var r = BitReader(Bytes())
        var pc2 = pc
        #expect(try pc2.readSymbol(&r) == 2)
    }

    @Test("over-subscribed code throws .invalidPrefixCode")
    func overSubscribed() {
        // Three length-1 codes is impossible (2 codes of length 1 max).
        #expect(throws: BrotliError.invalidPrefixCode) {
            _ = try PrefixCode(lengths: [1, 1, 1], maxBits: 4)
        }
    }
}

@Suite("InsertCopy.decompose")
struct InsertCopyTests {
    @Test("symbol 0 → cell 0: insertCode=0, copyCode=0, useDistance=false")
    func cell0First() throws {
        let r = try InsertCopy.decompose(0)
        #expect(r.insertCode == 0)
        #expect(r.copyCode == 0)
        #expect(r.useDistance == false)
    }

    @Test("symbol 63 → cell 0 last: insertCode=7, copyCode=7, useDistance=false")
    func cell0Last() throws {
        let r = try InsertCopy.decompose(63)
        #expect(r.insertCode == 7)
        #expect(r.copyCode == 7)
        #expect(r.useDistance == false)
    }

    @Test("symbol 64 → cell 1: insertCode=0, copyCode=8, useDistance=false (distance reuse)")
    func cell1First() throws {
        let r = try InsertCopy.decompose(64)
        #expect(r.insertCode == 0)
        #expect(r.copyCode == 8)
        #expect(r.useDistance == false)
    }

    @Test("symbol 128 → cell 2: useDistance=true (first distance-reading cell)")
    func cell2First() throws {
        let r = try InsertCopy.decompose(128)
        #expect(r.insertCode == 0)
        #expect(r.copyCode == 0)
        #expect(r.useDistance == true)
    }

    @Test("symbol 703 → cell 10 last: insertCode=23, copyCode=23, useDistance=true")
    func lastSymbol() throws {
        let r = try InsertCopy.decompose(703)
        #expect(r.insertCode == 23)
        #expect(r.copyCode == 23)
        #expect(r.useDistance == true)
    }

    @Test("out-of-range symbol throws")
    func outOfRange() {
        #expect(throws: BrotliError.invalidPrefixCode) {
            _ = try InsertCopy.decompose(704)
        }
    }
}

@Suite("DistanceDecoder")
struct DistanceDecoderTests {
    @Test("symbol 0 returns most-recent (4) without push")
    func symbol0NoPush() throws {
        var d = DistanceDecoder(ndirect: 0, npostfix: 0)
        var r = BitReader(Bytes())
        let v = try d.decode(symbol: 0, &r)
        #expect(v == 4)
        // ringBuffer unchanged
        #expect(d.ringBuffer == [16, 15, 11, 4])
        #expect(d.ringPos == 0)
    }

    @Test("symbols 0..3 reference last/second/third/fourth")
    func smallSymbols() throws {
        // Each symbol 1..3 pushes, so check in isolation.
        for (sym, expected) in [(0, 4), (1, 11), (2, 15), (3, 16)] {
            var d = DistanceDecoder(ndirect: 0, npostfix: 0)
            var r = BitReader(Bytes())
            let v = try d.decode(symbol: sym, &r)
            #expect(v == expected, "symbol \(sym) should resolve to \(expected), got \(v)")
        }
    }

    @Test("symbols 4..9: last ± k pattern")
    func smallLastAdjusted() throws {
        // last = 4, so:
        //   4 → 3 (4-1), 5 → 5 (4+1), 6 → 2, 7 → 6, 8 → 1, 9 → 7
        let cases: [(Int, Int)] = [(4, 3), (5, 5), (6, 2), (7, 6), (8, 1), (9, 7)]
        for (sym, expected) in cases {
            var d = DistanceDecoder(ndirect: 0, npostfix: 0)
            var r = BitReader(Bytes())
            let v = try d.decode(symbol: sym, &r)
            #expect(v == expected, "symbol \(sym) → \(expected); got \(v)")
        }
    }

    @Test("direct distance with NDIRECT")
    func directDistance() throws {
        var d = DistanceDecoder(ndirect: 4, npostfix: 0)
        var r = BitReader(Bytes())
        // Symbol 16 → distance 1, 17 → 2, 18 → 3, 19 → 4 (all direct).
        for (sym, expected) in [(16, 1), (17, 2), (18, 3), (19, 4)] {
            var fresh = DistanceDecoder(ndirect: 4, npostfix: 0)
            let v = try fresh.decode(symbol: sym, &r)
            #expect(v == expected)
        }
        _ = d
    }

    @Test("postfix formula symbol 16 (NDIRECT=0, NPOSTFIX=0)")
    func postfixSymbol16() throws {
        var d = DistanceDecoder(ndirect: 0, npostfix: 0)
        // dcode=16, base=0, hcode=0, lcode=0, ndistbits=1
        // extra=0: offset = ((2 + 0) << 1) - 4 = 0; distance = ((0+0)<<0) + 0 + 0 + 1 = 1
        var r = BitReader(Bytes([0x00]))  // extra bit = 0
        let v = try d.decode(symbol: 16, &r)
        #expect(v == 1)
    }
}

@Suite("Brotli decode vectors (generated by python -m brotli)")
struct BrotliVectorTests {
    @Test("empty input → 0x3B")
    func empty() throws {
        let compressed = Bytes([0x3B])
        let plain = try Brotli.decode(compressed)
        #expect(plain.storage == [])
    }

    @Test("single byte 'a'")
    func oneByte() throws {
        let compressed = Bytes([0x0B, 0x00, 0x80, 0x61, 0x03])
        let plain = try Brotli.decode(compressed)
        #expect(plain.storage == [0x61])
    }

    @Test("hello world")
    func helloWorld() throws {
        let compressed = Bytes([0x0B, 0x05, 0x80, 0x68, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0x77, 0x6F, 0x72, 0x6C, 0x64, 0x03])
        let plain = try Brotli.decode(compressed)
        #expect(String(decoding: plain.storage, as: UTF8.self) == "hello world")
    }

    @Test("pangram")
    func pangram() throws {
        let compressed = Bytes([0x8B, 0x15, 0x80, 0x54, 0x68, 0x65, 0x20, 0x71, 0x75, 0x69, 0x63, 0x6B, 0x20, 0x62, 0x72, 0x6F, 0x77, 0x6E, 0x20, 0x66, 0x6F, 0x78, 0x20, 0x6A, 0x75, 0x6D, 0x70, 0x73, 0x20, 0x6F, 0x76, 0x65, 0x72, 0x20, 0x74, 0x68, 0x65, 0x20, 0x6C, 0x61, 0x7A, 0x79, 0x20, 0x64, 0x6F, 0x67, 0x2E, 0x03])
        let plain = try Brotli.decode(compressed)
        #expect(String(decoding: plain.storage, as: UTF8.self) ==
                "The quick brown fox jumps over the lazy dog.")
    }

    @Test("32 'a's (LZ77 back-reference)")
    func thirtyTwoAs() throws {
        let compressed = Bytes([0x1B, 0x1F, 0x00, 0xF8, 0x25, 0xC2, 0x82, 0x8C, 0x00, 0xC0])
        let plain = try Brotli.decode(compressed)
        #expect(plain.storage == ContiguousArray(repeating: UInt8(0x61), count: 32))
    }

    @Test("256-byte repeating 4-byte pattern")
    func pattern256() throws {
        let compressed = Bytes([0x1B, 0xFF, 0x00, 0xF8, 0xA5, 0x03, 0x04, 0x06, 0x08, 0xC4, 0x68, 0x01, 0x80, 0x0D, 0x1B])
        let plain = try Brotli.decode(compressed)
        var expected = ContiguousArray<UInt8>()
        for _ in 0..<64 { expected.append(contentsOf: [0x01, 0x02, 0x03, 0x04]) }
        #expect(plain.storage == expected)
    }

    @Test("1024 'a's")
    func kiloA() throws {
        let compressed = Bytes([0x1B, 0xFF, 0x03, 0xF8, 0x25, 0xC2, 0xA2, 0xB1, 0x40, 0x20, 0x37])
        let plain = try Brotli.decode(compressed)
        #expect(plain.storage == ContiguousArray(repeating: UInt8(0x61), count: 1024))
    }
}

@Suite("Brotli decode errors")
struct BrotliErrorTests {
    @Test("empty input throws .truncated")
    func emptyTruncated() {
        #expect(throws: BrotliError.truncated) {
            try Brotli.decode(Bytes())
        }
    }

    @Test("truncated mid-meta-block-header throws")
    func truncatedHeader() {
        // 0x80 = bit 0 = 0 (WBITS=16), then header bits start. Not enough
        // bytes to even read the ISLAST bit cleanly past the WBITS — reaches
        // .truncated from BitReader.
        #expect(throws: BrotliError.truncated) {
            try Brotli.decode(Bytes([0x80]))
        }
    }

    @Test("reserved WBITS encoding throws .invalidHeader")
    func reservedWbits() {
        // bit 0 = 1, bits 1..3 = 000, bits 4..6 = 000 → reserved per § 9.1.
        #expect(throws: BrotliError.invalidHeader) {
            try Brotli.decode(Bytes([0x01, 0x00]))
        }
    }
}
