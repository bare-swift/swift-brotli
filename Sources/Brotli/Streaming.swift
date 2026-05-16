// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes

extension Brotli.Streaming {
    /// Streaming Brotli encoder. Feed chunks via ``update(_:)`` and
    /// terminate with ``finish()``. The encoder emits one Brotli metablock
    /// per ``update(_:)`` call (or N metablocks if a chunk exceeds 16 MiB).
    /// Each metablock is independent — no LZ77 match search crosses chunk
    /// boundaries in v0.3 (deferred to v0.4 for ratio improvement).
    ///
    /// Usage:
    /// ```swift
    /// var encoder = try Brotli.Streaming.Encoder(quality: .default)
    /// encoder.update(chunk1)
    /// encoder.update(chunk2)
    /// let compressed = try encoder.finish()
    /// let plain = try Brotli.decode(compressed)
    /// // plain == chunk1 + chunk2
    /// ```
    ///
    /// `Encoder` is a value type. Copying mid-stream produces two divergent
    /// encoders — each accumulates its own bytes from the copy point.
    /// Treat the encoder as single-owner.
    ///
    /// After ``finish()`` the encoder is in the finished state. Subsequent
    /// ``update(_:)`` calls are silent no-ops; subsequent ``finish()`` calls
    /// throw ``BrotliError/encoderFinished``.
    public struct Encoder: Sendable {
        private enum State: Sendable {
            case open
            case finished
        }

        private let quality: Brotli.Quality
        private var writer: BitWriter
        private var state: State

        public init(quality: Brotli.Quality = .default) throws(BrotliError) {
            let q = quality.rawValue
            guard q >= 0 && q <= 11 else { throw .qualityOutOfRange }
            self.quality = quality
            self.writer = BitWriter()
            self.state = .open

            // Emit stream header (WBITS=22) — matches Encoder.encode.
            // Per RFC 7932 § 9.1: first bit 1, next 3 bits = WBITS-17 = 5
            // LSB-first.
            self.writer.writeBit(1)
            self.writer.writeBits(5, count: 3)
        }

        /// Feed a chunk to the encoder. Emits one Brotli metablock per call
        /// (or N metablocks if `chunk.count > Brotli.maxInputSize`).
        /// Empty chunk = no-op (no metablock emitted).
        /// Silent no-op when called after ``finish()``.
        public mutating func update(_ chunk: Bytes) {
            guard case .open = state else { return }
            if chunk.isEmpty { return }

            // Split chunks > 16 MiB into multiple metablocks.
            let cap = Brotli.maxInputSize
            let total = chunk.count
            let bytes = Array(chunk)
            var offset = 0
            while offset < total {
                let end = Swift.min(offset + cap, total)
                let subChunk = Bytes(Array(bytes[offset..<end]))
                let commands = MatchFinder.scan(subChunk, quality: quality)
                EncoderMetaBlock.emit(
                    commands: commands,
                    inputSize: subChunk.count,
                    isLast: false,
                    to: &writer
                )
                offset = end
            }
        }

        /// Emit the terminator metablock (ISLAST=1, ISLASTEMPTY=1),
        /// byte-align, and return accumulated stream bytes. Throws
        /// ``BrotliError/encoderFinished`` on double-call.
        public mutating func finish() throws(BrotliError) -> Bytes {
            guard case .open = state else { throw .encoderFinished }
            state = .finished

            // Terminator metablock: ISLAST=1, ISLASTEMPTY=1 (2 bits).
            EncoderMetaBlock.emit(
                commands: [],
                inputSize: 0,
                isLast: true,
                to: &writer
            )

            writer.alignToByte()
            return writer.finalize()
        }
    }
}
