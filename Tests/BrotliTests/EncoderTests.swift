// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

import Testing
import Bytes
@testable import Brotli

@Suite("Encoder API surface")
struct EncoderAPITests {
    @Test("Quality.rawValue maps named cases to RFC 7932 levels")
    func qualityLevels() {
        #expect(Brotli.Quality.fastest.rawValue == 0)
        #expect(Brotli.Quality.fast.rawValue == 4)
        #expect(Brotli.Quality.default.rawValue == 6)
        #expect(Brotli.Quality.balanced.rawValue == 9)
        #expect(Brotli.Quality.smallest.rawValue == 11)
        #expect(Brotli.Quality.level(7).rawValue == 7)
    }

    @Test("BrotliError gains inputTooLarge + qualityOutOfRange cases")
    func newErrorCases() {
        let a: BrotliError = .inputTooLarge
        let b: BrotliError = .qualityOutOfRange
        #expect(a != b)
    }

    @Test("compress with empty input returns a non-empty valid brotli stream")
    func emptyInputCompresses() throws {
        let out = try Brotli.compress(Bytes())
        #expect(!out.isEmpty)
    }
}

@Suite("BitWriter")
struct BitWriterTests {
    @Test("writes a single byte 0x06 across three 1-bit calls")
    func smallByte() {
        var w = BitWriter()
        w.writeBits(0, count: 1)
        w.writeBits(1, count: 1)
        w.writeBits(1, count: 1)
        w.alignToByte()
        let out = w.finalize()
        #expect(out.count == 1)
        #expect(out[0] == 0x06)
    }

    @Test("writes a multi-byte value LSB-first")
    func multiByte() {
        var w = BitWriter()
        w.writeBits(0x1234, count: 16)
        let out = w.finalize()
        #expect(out.count == 2)
        #expect(out[0] == 0x34)
        #expect(out[1] == 0x12)
    }

    @Test("writeBit convenience")
    func singleBit() {
        var w = BitWriter()
        for _ in 0..<8 { w.writeBit(1) }
        let out = w.finalize()
        #expect(out.count == 1)
        #expect(out[0] == 0xFF)
    }

    @Test("alignToByte pads with zeros")
    func alignment() {
        var w = BitWriter()
        w.writeBits(0b101, count: 3)
        w.alignToByte()
        let out = w.finalize()
        #expect(out.count == 1)
        #expect(out[0] == 0b00000101)
    }

    @Test("finalize without explicit align flushes partial byte")
    func implicitFinalize() {
        var w = BitWriter()
        w.writeBits(0b11, count: 2)
        let out = w.finalize()
        #expect(out.count == 1)
        #expect(out[0] == 0b00000011)
    }

    @Test("writes >16 bits across alternating-bit calls")
    func longSequence() {
        var w = BitWriter()
        for i in 0..<20 { w.writeBits(UInt32(i & 1), count: 1) }
        let out = w.finalize()
        #expect(out.count == 3)
        #expect(out[0] == 0xAA)
        #expect(out[1] == 0xAA)
        #expect(out[2] == 0x0A)
    }
}
