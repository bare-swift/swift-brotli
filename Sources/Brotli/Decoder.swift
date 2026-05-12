// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

import Bytes

/// Top-level brotli decode driver per RFC 7932 § 9.
/// **Stage A skeleton:** dispatches to the foundational machinery but the
/// full meta-block decode loop ships in Stage B per the implementation plan.
enum Decoder {
    static func decode(_ bytes: Bytes, outputCap: Int) throws(BrotliError) -> Bytes {
        var reader = BitReader(bytes)
        // Read the stream header so callers at least exercise the bit
        // reader + WBITS parser before we hit the unimplemented core.
        // An empty input fails here with .truncated.
        _ = try StreamHeader.readWBITS(&reader)
        // Drain meta-blocks; the empty-final case decodes cleanly.
        let header = try MetaBlockHeader.read(&reader)
        if header.isLastEmpty {
            return Bytes()
        }
        // Compressed and uncompressed meta-block payload decoding lands
        // in Stage B (Task 15 of the implementation plan). For now any
        // non-empty meta-block reports `.invalidMetaBlockHeader` so
        // callers know the path is unimplemented without crashing.
        throw .invalidMetaBlockHeader
    }
}
