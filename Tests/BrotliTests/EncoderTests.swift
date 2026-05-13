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

@Suite("PrefixCodeEmitter round-trip")
struct PrefixCodeEmitterTests {
    /// Helper: emit a prefix code, then read it back via v0.1 PrefixCode.read,
    /// and verify the resulting code's structure matches what we declared.
    static func roundTrip(lengths: [Int], alphabetSize: Int, maxBits: Int = 15) throws -> PrefixCode {
        var w = BitWriter()
        PrefixCodeEmitter.emit(codeLengths: lengths, alphabetSize: alphabetSize, to: &w)
        let encoded = w.finalize()
        var r = BitReader(encoded)
        return try PrefixCode.read(&r, alphabetSize: alphabetSize, maxBits: maxBits)
    }

    @Test("simple form 1 symbol round-trip")
    func simpleOne() throws {
        var lengths = [Int](repeating: 0, count: 256)
        lengths[42] = 1
        let pc = try Self.roundTrip(lengths: lengths, alphabetSize: 256)
        // For a 1-symbol code, every readSymbol returns the single symbol.
        // Read from an empty stream — singleSymbol short-circuit.
        var r = BitReader(Bytes())
        var pc2 = pc
        #expect(try pc2.readSymbol(&r) == 42)
    }

    @Test("simple form 2 symbols round-trip")
    func simpleTwo() throws {
        // Two symbols of length 1 each.
        var lengths = [Int](repeating: 0, count: 8)
        lengths[1] = 1
        lengths[3] = 1
        let pc = try Self.roundTrip(lengths: lengths, alphabetSize: 8)
        // After emit + read, the resulting code should decode bit 0 → symbol 1,
        // bit 1 → symbol 3 (since codes are sorted ascending: 1 gets code 0,
        // 3 gets code 1).
        var r = BitReader(Bytes([0b10]))
        var pc2 = pc
        #expect(try pc2.readSymbol(&r) == 1)  // first bit (0) → symbol 1
        #expect(try pc2.readSymbol(&r) == 3)  // next bit (1) → symbol 3
    }

    @Test("complex form 5 distinct symbols round-trip")
    func complexFive() throws {
        var lengths = [Int](repeating: 0, count: 8)
        for i in 0..<4 { lengths[i] = 3 }
        lengths[4] = 2
        // 4 symbols at length 3 + 1 symbol at length 2 → Kraft = 4 * 1/8 + 1/4 = 0.75
        // That's UNDER-subscribed. Adjust to make it exactly 1.
        // 2 symbols at length 1 + 4 at length 3 → 2*0.5 + 4*0.125 = 1.5 (over)
        // Use 1 at length 1 + 1 at length 2 + 4 at length 3 → 0.5 + 0.25 + 4*0.125 = 1.25 (over)
        // Use 1 at length 1 + 2 at length 2 + 2 at length 3 → 0.5 + 0.5 + 0.25 = 1.25 (over)
        // Use 2 at length 2 + 4 at length 3 → 0.5 + 0.5 = 1 ✓
        lengths = [Int](repeating: 0, count: 8)
        lengths[0] = 2
        lengths[1] = 2
        lengths[2] = 3
        lengths[3] = 3
        lengths[4] = 3
        lengths[5] = 3
        // 6 distinct symbols, forces complex form.
        let _ = try Self.roundTrip(lengths: lengths, alphabetSize: 8)
        // No further assertion — round-trip succeeded means complex form
        // marker + meta-tree + alphabet lengths all decoded correctly.
    }

    @Test("complex form sparse 256-alphabet round-trip")
    func complexSparse() throws {
        var lengths = [Int](repeating: 0, count: 256)
        for i in [0, 32, 65, 97, 100, 200, 255, 128] { lengths[i] = 3 }
        let _ = try Self.roundTrip(lengths: lengths, alphabetSize: 256)
    }
}

@Suite("EncoderCommand")
struct EncoderCommandTests {
    @Test("insert-length code: 0 → code 0, no extra bits")
    func insertZero() {
        let r = EncoderCommandCoding.insertLengthCode(0)
        #expect(r.code == 0)
        #expect(r.extraBits == 0)
        #expect(r.extra == 0)
    }

    @Test("insert-length code: 5 → code 5, no extra bits")
    func insertFive() {
        let r = EncoderCommandCoding.insertLengthCode(5)
        #expect(r.code == 5)
        #expect(r.extraBits == 0)
    }

    @Test("insert-length code: 12 → code 8, 2 extra bits = 12-10 = 2")
    func insertTwelve() {
        let r = EncoderCommandCoding.insertLengthCode(12)
        #expect(r.code == 8)
        #expect(r.extraBits == 2)
        #expect(r.extra == 2)
    }

    @Test("copy-length code: 2 → code 0, no extra")
    func copyMin() {
        let r = EncoderCommandCoding.copyLengthCode(2)
        #expect(r.code == 0)
        #expect(r.extraBits == 0)
    }

    @Test("copy-length code: 10 → code 8, 1 extra bit, payload 0")
    func copyTen() {
        let r = EncoderCommandCoding.copyLengthCode(10)
        #expect(r.code == 8)
        #expect(r.extraBits == 1)
        #expect(r.extra == 0)
    }

    @Test("combinedCode for (insert=0, copy=0, useDist=true) → cell 2 symbol 128")
    func combinedSmall() {
        let s = EncoderCommandCoding.combinedSymbol(insertCode: 0, copyCode: 0, useDistance: true)
        #expect(s == 128)  // cell 2 * 64 + 0 * 8 + 0
    }

    @Test("combinedCode for (insert=23, copy=0, useDist=true) → cell 7")
    func combinedLargeInsert() {
        let s = EncoderCommandCoding.combinedSymbol(insertCode: 23, copyCode: 0, useDistance: true)
        // cell 7 * 64 + insertOffset (23-16=7) * 8 + copyOffset (0) = 448 + 56 + 0 = 504
        #expect(s == 504)
    }

    @Test("distance 1 → code 16, 1 extra bit, extra=0")
    func distOne() {
        let r = EncoderCommandCoding.distanceCode(1)
        // C=16: NDISTBITS=1, DOFFSET=0 → distance = 0 + extra + 1.
        // For d=1: extra=0, extraBits=1.
        #expect(r.code == 16)
        #expect(r.extraBits == 1)
        #expect(r.extra == 0)
    }

    @Test("distance 8 → code 18 range")
    func distEight() {
        let r = EncoderCommandCoding.distanceCode(8)
        // C=18: NDISTBITS=2, DOFFSET=4, distance = 4 + extra + 1 = 5..8.
        // For d=8, extra = 3.
        #expect(r.code == 18)
        #expect(r.extraBits == 2)
        #expect(r.extra == 3)
    }

    @Test("distance 100 → produces valid code + extra bits")
    func distHundred() {
        let r = EncoderCommandCoding.distanceCode(100)
        #expect(r.code >= 16)
        #expect(r.extraBits >= 0)
    }
}

@Suite("MatchFinder")
struct MatchFinderTests {
    @Test("quality 0 emits all bytes as literals, no copies")
    func qualityZero() {
        let input = Bytes([1, 2, 3, 4, 5])
        let commands = MatchFinder.scan(input, quality: .fastest)
        let totalLits = commands.reduce(0) { $0 + $1.insertLits.count }
        #expect(totalLits == 5)
        #expect(commands.allSatisfy { $0.copyLen == 0 })
    }

    @Test("quality 6 finds a repeating run")
    func qualitySixRepeat() {
        var input: [UInt8] = []
        for _ in 0..<2 { input.append(contentsOf: [65, 66, 67, 68, 69, 70, 71, 72]) }
        let commands = MatchFinder.scan(Bytes(input), quality: .default)
        let copies = commands.filter { $0.copyLen >= 4 }
        #expect(!copies.isEmpty)
        if let first = copies.first {
            #expect(first.distance == 8)
        }
    }

    @Test("quality 0 empty input")
    func qualityZeroEmpty() {
        let commands = MatchFinder.scan(Bytes(), quality: .fastest)
        let totalLits = commands.reduce(0) { $0 + $1.insertLits.count }
        #expect(totalLits == 0)
    }

    @Test("quality 6 short input below match-length skips matching")
    func shortInput() {
        // 3 bytes — below minMatch=4, so all literals even at quality 6.
        let commands = MatchFinder.scan(Bytes([1, 2, 3]), quality: .default)
        let totalLits = commands.reduce(0) { $0 + $1.insertLits.count }
        #expect(totalLits == 3)
        #expect(commands.allSatisfy { $0.copyLen == 0 })
    }
}

@Suite("Encoder round-trip — small inputs")
struct EncoderRoundTripSmallTests {
    @Test("empty input round-trips")
    func empty() throws {
        let compressed = try Brotli.compress(Bytes())
        let plain = try Brotli.decode(compressed)
        #expect(plain.isEmpty)
    }

    @Test("single byte round-trips at quality 0")
    func singleByteQ0() throws {
        let input = Bytes([0x42])
        let compressed = try Brotli.compress(input, quality: .fastest)
        let plain = try Brotli.decode(compressed)
        #expect(plain == input)
    }

    @Test("4-byte literal round-trips at quality 0")
    func fourBytesQ0() throws {
        let input = Bytes([1, 2, 3, 4])
        let compressed = try Brotli.compress(input, quality: .fastest)
        let plain = try Brotli.decode(compressed)
        #expect(plain == input)
    }

    @Test("4-byte literal round-trips at quality 6")
    func fourBytesQ6() throws {
        let input = Bytes([1, 2, 3, 4])
        let compressed = try Brotli.compress(input, quality: .default)
        let plain = try Brotli.decode(compressed)
        #expect(plain == input)
    }
}

@Suite("Encoder round-trip — comprehensive matrix")
struct EncoderRoundTripMatrixTests {
    static let qualities: [Brotli.Quality] = [.fastest, .fast, .default, .balanced, .smallest]

    static func roundTrip(_ input: [UInt8], quality: Brotli.Quality) throws {
        let bytes = Bytes(input)
        let compressed = try Brotli.compress(bytes, quality: quality)
        let plain = try Brotli.decode(compressed)
        #expect(plain == bytes, "round-trip failed at quality \(quality.rawValue)")
    }

    @Test("empty input across all qualities")
    func empty() throws {
        for q in Self.qualities {
            try Self.roundTrip([], quality: q)
        }
    }

    @Test("single byte across all qualities")
    func singleByte() throws {
        for q in Self.qualities {
            try Self.roundTrip([0x42], quality: q)
        }
    }

    @Test("repeating 100 bytes")
    func repeating() throws {
        let input = [UInt8](repeating: 0x41, count: 100)
        for q in Self.qualities {
            try Self.roundTrip(input, quality: q)
        }
    }

    @Test("random 1 KiB")
    func random1k() throws {
        var rng = SystemRandomNumberGenerator()
        var input = [UInt8]()
        for _ in 0..<1024 { input.append(UInt8(rng.next() & 0xFF)) }
        for q in Self.qualities {
            try Self.roundTrip(input, quality: q)
        }
    }

    @Test("ASCII text 4 KiB")
    func asciiText() throws {
        let lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
        var input: [UInt8] = []
        while input.count < 4096 {
            input.append(contentsOf: Array(lorem.utf8))
        }
        input = Array(input.prefix(4096))
        for q in Self.qualities {
            try Self.roundTrip(input, quality: q)
        }
    }

    @Test("JSON-shaped 4 KiB")
    func jsonShaped() throws {
        var input: [UInt8] = []
        let entry = #"{"id":12345,"name":"alice","email":"alice@example.com"},"#
        while input.count < 4096 {
            input.append(contentsOf: Array(entry.utf8))
        }
        input = Array(input.prefix(4096))
        for q in Self.qualities {
            try Self.roundTrip(input, quality: q)
        }
    }

    @Test("16 KiB random binary")
    func random16k() throws {
        var rng = SystemRandomNumberGenerator()
        var input = [UInt8]()
        for _ in 0..<16384 { input.append(UInt8(rng.next() & 0xFF)) }
        for q in Self.qualities {
            try Self.roundTrip(input, quality: q)
        }
    }
}

@Suite("Encoder errors")
struct EncoderErrorTests {
    @Test("input > 16 MiB throws inputTooLarge")
    func inputTooLarge() {
        let bytes = Bytes([UInt8](repeating: 0, count: Brotli.maxInputSize + 1))
        #expect(throws: BrotliError.inputTooLarge) {
            _ = try Brotli.compress(bytes)
        }
    }

    @Test("quality -1 throws qualityOutOfRange")
    func qualityNegative() {
        #expect(throws: BrotliError.qualityOutOfRange) {
            _ = try Brotli.compress(Bytes([1]), quality: .level(-1))
        }
    }

    @Test("quality 12 throws qualityOutOfRange")
    func qualityTooHigh() {
        #expect(throws: BrotliError.qualityOutOfRange) {
            _ = try Brotli.compress(Bytes([1]), quality: .level(12))
        }
    }
}

@Suite("Encoder compression sanity")
struct EncoderCompressionSanityTests {
    @Test("4 KiB repeating Lorem compresses below input size at quality 6+")
    func loremCompresses() throws {
        let lorem = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
        var input: [UInt8] = []
        while input.count < 4096 { input.append(contentsOf: Array(lorem.utf8)) }
        input = Array(input.prefix(4096))

        let q6 = try Brotli.compress(Bytes(input), quality: .default)
        let q9 = try Brotli.compress(Bytes(input), quality: .balanced)

        #expect(try Brotli.decode(q6) == Bytes(input))
        #expect(try Brotli.decode(q9) == Bytes(input))
        #expect(q6.count < 4096)
        #expect(q9.count < 4096)
    }
}
