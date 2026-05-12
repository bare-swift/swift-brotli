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
