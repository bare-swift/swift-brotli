// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes

/// Brotli output buffer with backward-reference support.
///
/// v0.1 uses a flat append-only buffer rather than a fixed-size ring,
/// because the whole output is held in memory (no streaming).
/// Dictionary-distance references append the transformed dictionary
/// word; see ``appendDictionaryWord(length:index:transform:)``.
struct OutputBuffer {
    private(set) var storage = ContiguousArray<UInt8>()
    let cap: Int

    init(cap: Int) {
        self.cap = cap
    }

    var count: Int { storage.count }

    /// Append one literal byte.
    mutating func appendLiteral(_ byte: UInt8) throws(BrotliError) {
        if storage.count >= cap { throw .outputTooLarge }
        storage.append(byte)
    }

    /// Append a sequence of literal bytes (e.g. from an uncompressed
    /// meta-block).
    mutating func appendLiterals(_ bytes: ContiguousArray<UInt8>) throws(BrotliError) {
        if storage.count + bytes.count > cap { throw .outputTooLarge }
        storage.append(contentsOf: bytes)
    }

    /// Copy `length` bytes from `count - distance` to the current end.
    /// Handles the RLE case (length > distance) byte-by-byte like DEFLATE.
    mutating func copy(distance: Int, length: Int) throws(BrotliError) {
        guard distance >= 1, distance <= storage.count else {
            throw .invalidDistance
        }
        if storage.count + length > cap { throw .outputTooLarge }
        let start = storage.count - distance
        for k in 0..<length {
            storage.append(storage[start + k])
        }
    }

    /// Append a transformed dictionary word. Wires `Dictionary` +
    /// `Transforms` into the output stream; called when a backward
    /// reference's distance exceeds the in-window output size.
    mutating func appendDictionaryWord(
        length: Int,
        index: Int,
        transform: Int
    ) throws(BrotliError) {
        guard length >= 4 && length <= 24 else {
            throw .invalidDictionaryReference
        }
        guard index >= 0 && index < Dictionary.counts[length] else {
            throw .invalidDictionaryReference
        }
        let offset = Dictionary.offsets[length] + index * length
        let wordSlice = Dictionary.bytes[offset ..< offset + length]
        let transformed = try Transforms.apply(transform, to: wordSlice)
        if storage.count + transformed.count > cap { throw .outputTooLarge }
        storage.append(contentsOf: transformed)
    }

    /// Last two bytes (for context modes); returns 0 for missing bytes.
    /// Order: `(p1, p2)` = (most-recent, second-most-recent).
    var lastTwo: (UInt8, UInt8) {
        switch storage.count {
        case 0: return (0, 0)
        case 1: return (storage[0], 0)
        default: return (storage[storage.count - 1], storage[storage.count - 2])
        }
    }

    func toBytes() -> Bytes {
        Bytes(storage)
    }
}
