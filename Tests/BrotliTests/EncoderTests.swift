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

@Suite("HuffmanBuilder")
struct HuffmanBuilderTests {
    @Test("all zeros input returns all zeros")
    func allZeros() {
        let lengths = HuffmanBuilder.build(frequencies: [0, 0, 0, 0], maxBits: 15)
        #expect(lengths == [0, 0, 0, 0])
    }

    @Test("single non-zero symbol → length 1 at that index")
    func singleSymbol() {
        let lengths = HuffmanBuilder.build(frequencies: [0, 0, 5, 0], maxBits: 15)
        #expect(lengths == [0, 0, 1, 0])
    }

    @Test("two symbols → both length 1")
    func twoSymbols() {
        let lengths = HuffmanBuilder.build(frequencies: [3, 5, 0, 0], maxBits: 15)
        #expect(lengths == [1, 1, 0, 0])
    }

    @Test("four equal-frequency symbols → all length 2")
    func fourEqual() {
        let lengths = HuffmanBuilder.build(frequencies: [1, 1, 1, 1], maxBits: 15)
        #expect(lengths == [2, 2, 2, 2])
    }

    @Test("Kraft inequality satisfied for skewed input")
    func kraftHolds() {
        let lengths = HuffmanBuilder.build(frequencies: [100, 50, 25, 10, 5, 1], maxBits: 15)
        var kraft = 0.0
        for L in lengths where L > 0 {
            kraft += 1.0 / Double(1 << L)
        }
        #expect(kraft <= 1.0 + 1e-9)
        #expect(kraft >= 0.5)
    }

    @Test("max-bits cap honored")
    func maxBitsCap() {
        var freqs = [Int](repeating: 0, count: 32)
        freqs[0] = 1_000_000
        for i in 1..<32 { freqs[i] = 1 }
        let lengths = HuffmanBuilder.build(frequencies: freqs, maxBits: 5)
        #expect(lengths.allSatisfy { $0 <= 5 })
        #expect(lengths[0] > 0)
    }

    @Test("canonicalCodes assigns deterministic codes")
    func canonical() {
        let lengths = [3, 3, 3, 3, 3, 2, 4, 4]
        let codes = HuffmanBuilder.canonicalCodes(from: lengths)
        #expect(codes[5] == 0b00)
        #expect(codes[0] == 0b010)
        #expect(codes[1] == 0b011)
        #expect(codes[2] == 0b100)
        #expect(codes[3] == 0b101)
        #expect(codes[4] == 0b110)
        #expect(codes[6] == 0b1110)
        #expect(codes[7] == 0b1111)
    }

    @Test("canonicalCodes blCount[0] reset")
    func blCountReset() {
        let lengths = [0, 0, 0, 2, 2, 2, 2]
        let codes = HuffmanBuilder.canonicalCodes(from: lengths)
        #expect(codes[3] == 0b00)
        #expect(codes[4] == 0b01)
        #expect(codes[5] == 0b10)
        #expect(codes[6] == 0b11)
    }
}
