// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

import Testing
import Bytes
@testable import Brotli

@Suite("Streaming encoder")
struct StreamingTests {
    // MARK: - Round-trip tests

    @Test("empty stream (no update + finish) round-trips to empty Bytes")
    func emptyStream() throws {
        var encoder = try Brotli.Streaming.Encoder()
        let compressed = try encoder.finish()
        let plain = try Brotli.decode(compressed)
        #expect(plain.isEmpty)
    }

    @Test("empty stream is byte-equal to Brotli.compress(empty)")
    func emptyStreamByteEqualsV02OneShot() throws {
        var encoder = try Brotli.Streaming.Encoder()
        let streamed = try encoder.finish()
        let oneShot = try Brotli.compress(Bytes())
        #expect(Array(streamed) == Array(oneShot))
    }

    @Test("single chunk update + finish round-trips")
    func singleChunkRoundTrip() throws {
        let payload = Bytes(Array("hello".utf8))
        var encoder = try Brotli.Streaming.Encoder()
        encoder.update(payload)
        let compressed = try encoder.finish()
        let plain = try Brotli.decode(compressed)
        #expect(Array(plain) == Array(payload))
    }

    @Test("two chunks round-trip to concatenation")
    func twoChunkRoundTrip() throws {
        let chunk1 = Bytes(Array("hel".utf8))
        let chunk2 = Bytes(Array("lo".utf8))
        var encoder = try Brotli.Streaming.Encoder()
        encoder.update(chunk1)
        encoder.update(chunk2)
        let compressed = try encoder.finish()
        let plain = try Brotli.decode(compressed)
        #expect(Array(plain) == Array(Bytes(Array("hello".utf8))))
    }

    @Test("many tiny 1-byte chunks round-trip")
    func manyTinyChunks() throws {
        let payload: [UInt8] = (0..<100).map { UInt8($0 & 0xFF) }
        var encoder = try Brotli.Streaming.Encoder()
        for byte in payload {
            encoder.update(Bytes([byte]))
        }
        let compressed = try encoder.finish()
        let plain = try Brotli.decode(compressed)
        #expect(Array(plain) == payload)
    }

    @Test("single chunk ≥16 MiB triggers internal multi-metablock split and round-trips")
    func oversizedChunkSplits() throws {
        // 16 MiB + 1 byte — one byte over Brotli.maxInputSize.
        let size = Brotli.maxInputSize + 1
        let payload = [UInt8](repeating: 0x41, count: size)
        var encoder = try Brotli.Streaming.Encoder(quality: .fastest)
        encoder.update(Bytes(payload))
        let compressed = try encoder.finish()
        let plain = try Brotli.decode(compressed)
        #expect(plain.count == size)
        #expect(Array(plain) == payload)
    }

    @Test("mixed-size chunks (pangram + small + medium) round-trip")
    func mixedSizeChunks() throws {
        let pangram = Bytes(Array("The quick brown fox jumps over the lazy dog. ".utf8))
        let small = Bytes(Array("XY".utf8))
        let medium = Bytes([UInt8](repeating: 0x42, count: 256))
        var encoder = try Brotli.Streaming.Encoder()
        encoder.update(pangram)
        encoder.update(small)
        encoder.update(medium)
        let compressed = try encoder.finish()
        let plain = try Brotli.decode(compressed)
        let expected = Array(pangram) + Array(small) + Array(medium)
        #expect(Array(plain) == expected)
    }

    @Test("empty chunk in middle is a no-op")
    func emptyChunkInMiddle() throws {
        var encoder = try Brotli.Streaming.Encoder()
        encoder.update(Bytes(Array("a".utf8)))
        encoder.update(Bytes())  // no-op
        encoder.update(Bytes(Array("b".utf8)))
        let compressed = try encoder.finish()
        let plain = try Brotli.decode(compressed)
        #expect(Array(plain) == Array("ab".utf8))
    }

    // MARK: - Quality coverage

    @Test(".fastest quality round-trip")
    func qualityFastest() throws {
        let payload = Bytes(Array("The quick brown fox jumps over the lazy dog.".utf8))
        var encoder = try Brotli.Streaming.Encoder(quality: .fastest)
        encoder.update(payload)
        let compressed = try encoder.finish()
        let plain = try Brotli.decode(compressed)
        #expect(Array(plain) == Array(payload))
    }

    @Test(".smallest quality round-trip")
    func qualitySmallest() throws {
        let payload = Bytes([UInt8](repeating: 0x5A, count: 1024))
        var encoder = try Brotli.Streaming.Encoder(quality: .smallest)
        encoder.update(payload)
        let compressed = try encoder.finish()
        let plain = try Brotli.decode(compressed)
        #expect(Array(plain) == Array(payload))
    }

    // MARK: - Equivalence with one-shot

    @Test("single-update output decodes to same bytes as Brotli.compress one-shot")
    func equivalenceToOneShot() throws {
        let payload = Bytes(Array("hello world hello world hello world".utf8))
        var encoder = try Brotli.Streaming.Encoder()
        encoder.update(payload)
        let streamed = try encoder.finish()
        let oneShot = try Brotli.compress(payload)
        let streamedDecoded = try Brotli.decode(streamed)
        let oneShotDecoded = try Brotli.decode(oneShot)
        #expect(Array(streamedDecoded) == Array(oneShotDecoded))
        #expect(Array(streamedDecoded) == Array(payload))
    }

    // MARK: - Error cases

    @Test("init with quality below 0 throws qualityOutOfRange")
    func qualityNegativeThrows() {
        do {
            _ = try Brotli.Streaming.Encoder(quality: .level(-1))
            Issue.record("expected throw")
        } catch BrotliError.qualityOutOfRange {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("init with quality above 11 throws qualityOutOfRange")
    func qualityAbove11Throws() {
        do {
            _ = try Brotli.Streaming.Encoder(quality: .level(12))
            Issue.record("expected throw")
        } catch BrotliError.qualityOutOfRange {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("double-finish throws encoderFinished")
    func doubleFinishThrows() throws {
        var encoder = try Brotli.Streaming.Encoder()
        encoder.update(Bytes(Array("data".utf8)))
        _ = try encoder.finish()
        do {
            _ = try encoder.finish()
            Issue.record("expected throw")
        } catch BrotliError.encoderFinished {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    // MARK: - Edge cases

    @Test("single-byte stream round-trips")
    func singleByteStream() throws {
        let payload = Bytes([0x7F])
        var encoder = try Brotli.Streaming.Encoder()
        encoder.update(payload)
        let compressed = try encoder.finish()
        let plain = try Brotli.decode(compressed)
        #expect(Array(plain) == [0x7F])
    }

    // MARK: - Drain (v0.4)

    @Test("drain() on fresh encoder returns empty Bytes")
    func drainFresh() throws {
        var encoder = try Brotli.Streaming.Encoder()
        let drained = encoder.drain()
        #expect(drained.count == 4 || drained.count == 0)
        // After init, the 4-bit stream header is in the partial-byte buffer
        // (NOT byte-aligned) so drain returns 0 bytes. (Empty stream header
        // is below 8 bits.)
        #expect(drained.count == 0)
    }

    @Test("drain() + finish() concatenated round-trips through decode")
    func drainConcatRoundTrip() throws {
        let payload = Bytes(Array("hello world hello world".utf8))
        var encoder = try Brotli.Streaming.Encoder()
        encoder.update(payload)
        let drained = encoder.drain()
        let final = try encoder.finish()

        // Concatenate drained + final bytes; should decode to original.
        var combined = Bytes()
        combined.append(contentsOf: drained.storage)
        combined.append(contentsOf: final.storage)
        let plain = try Brotli.decode(combined)
        #expect(Array(plain.storage) == Array(payload.storage))
    }

    @Test("multiple drains + finish round-trip equals single-finish round-trip")
    func multipleDrains() throws {
        let chunk1 = Bytes(Array("first".utf8))
        let chunk2 = Bytes(Array("second".utf8))
        let chunk3 = Bytes(Array("third".utf8))

        // Streaming with drains between updates.
        var draining = try Brotli.Streaming.Encoder()
        draining.update(chunk1)
        var collected = Bytes()
        collected.append(contentsOf: draining.drain().storage)
        draining.update(chunk2)
        collected.append(contentsOf: draining.drain().storage)
        draining.update(chunk3)
        collected.append(contentsOf: draining.drain().storage)
        collected.append(contentsOf: (try draining.finish()).storage)

        let drainedDecoded = try Brotli.decode(collected)
        let expected = Array("firstsecondthird".utf8)
        #expect(Array(drainedDecoded.storage) == expected)
    }

    @Test("drain after finish is silent no-op (empty Bytes)")
    func drainAfterFinish() throws {
        var encoder = try Brotli.Streaming.Encoder()
        encoder.update(Bytes(Array("data".utf8)))
        _ = try encoder.finish()
        let drained = encoder.drain()
        #expect(drained.count == 0)
    }

    @Test("non-draining stream byte-equals concatenated-drains stream")
    func drainConcatByteEquality() throws {
        let chunk1 = Bytes(Array("aaaaaaaaaa".utf8))
        let chunk2 = Bytes(Array("bbbbbbbbbb".utf8))

        // Reference: never drain.
        var reference = try Brotli.Streaming.Encoder()
        reference.update(chunk1)
        reference.update(chunk2)
        let referenceOutput = try reference.finish()

        // With drains.
        var draining = try Brotli.Streaming.Encoder()
        draining.update(chunk1)
        let d1 = draining.drain()
        draining.update(chunk2)
        let d2 = draining.drain()
        let d3 = try draining.finish()

        var combined = Bytes()
        combined.append(contentsOf: d1.storage)
        combined.append(contentsOf: d2.storage)
        combined.append(contentsOf: d3.storage)

        // Bytes are identical because drain preserves the partial-byte
        // buffer; concatenation is bit-perfect.
        #expect(Array(combined.storage) == Array(referenceOutput.storage))
    }

    // MARK: - Existing v0.3 edge cases

    @Test("update after finish is silent no-op (then double-finish throws)")
    func updateAfterFinishNoOp() throws {
        var encoder = try Brotli.Streaming.Encoder()
        encoder.update(Bytes(Array("first".utf8)))
        let compressed = try encoder.finish()
        // update on finished encoder should be silent no-op (no throw).
        encoder.update(Bytes(Array("second".utf8)))
        // Double-finish still throws encoderFinished.
        do {
            _ = try encoder.finish()
            Issue.record("expected throw on second finish")
        } catch BrotliError.encoderFinished {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        // Decode confirms only "first" was encoded.
        let plain = try Brotli.decode(compressed)
        #expect(Array(plain) == Array("first".utf8))
    }
}
