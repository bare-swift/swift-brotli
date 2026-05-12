// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// Errors thrown by ``Brotli/decode(_:)``.
public enum BrotliError: Error, Equatable, Sendable {
    /// Decoder ran out of bytes mid-stream.
    case truncated

    /// Stream header violated RFC 7932 § 9.1 (e.g. impossible WBITS encoding).
    case invalidHeader

    /// Prefix-code declaration was over- or under-subscribed, or used a
    /// reserved length/code combination.
    case invalidPrefixCode

    /// Context mode (CMODE) outside the legal 0..3 range per § 7.1.
    case invalidContextMode

    /// Block-type index outside `NBLTYPES{L,I,D}` range per § 6.
    case invalidBlockType

    /// Distance code resolved to a value ≤ 0 or pointed before the start
    /// of the output stream.
    case invalidDistance

    /// Dictionary reference (distance-class word) had an out-of-range
    /// length/index per § 8.
    case invalidDictionaryReference

    /// Static-dictionary transform produced an output longer than its
    /// permitted maximum per § 8 Table 2.
    case invalidTransform

    /// Meta-block header had an illegal MLEN / MSKIPBYTES encoding per § 9.2.
    case invalidMetaBlockHeader

    /// Output buffer hit an implementation-imposed cap (64 MiB by default).
    case outputTooLarge
}
