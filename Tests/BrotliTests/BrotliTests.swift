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
             .invalidTransform, .invalidMetaBlockHeader, .outputTooLarge:
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
