# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-05-12

### Added
- `Brotli.decode(_ bytes: Bytes) throws(BrotliError) -> Bytes` — single-shot RFC 7932 decoder.
- `BrotliError` typed-throws enum (10 cases): `truncated`, `invalidHeader`, `invalidPrefixCode`, `invalidContextMode`, `invalidBlockType`, `invalidDistance`, `invalidDictionaryReference`, `invalidTransform`, `invalidMetaBlockHeader`, `outputTooLarge`.
- Full meta-block support (compressed / uncompressed / empty + multi-meta-block streams).
- Six literal context modes (LSB6 / MSB6 / UTF8 / Signed).
- § 7.3 context maps with RLE expansion and optional Inverse Move-to-Front transform.
- § 4 distance ring buffer (initialized `[16, 15, 11, 4]` at stream start; symbol 0 reuses without push; static-dictionary refs don't push).
- All 121 § 8 static-dictionary transforms (identity / omitLast{1..9} / omitFirst{1..9} / uppercaseFirst / uppercaseAll, with UTF-8-aware case folding).
- Output cap of 64 MiB (configurable in a future v0.x patch).
- 53 tests across 12 suites covering API surface, BitReader, StreamHeader, MetaBlockHeader, OutputBuffer, Transforms (9 tests), ContextMap LUTs, PrefixCode (incl. RFC § 3.2 example), InsertCopy decomposition, DistanceDecoder, end-to-end vectors from `python -m brotli` (empty / single byte / hello world / pangram / 32 As / 256-byte pattern / 1024 As), and error paths.

### Source attribution
- Static dictionary (`Sources/Brotli/Dictionary.swift`, 122 784 bytes), transforms table (`Sources/Brotli/Transforms.swift`, 121 entries), and context-mode LUTs (`Sources/Brotli/ContextMap.swift`, 4 × 512 bytes) are derived from Google's brotli project (MIT-licensed). See NOTICE.
- The algorithmic implementation is a clean-room Swift port of RFC 7932.

### Dependencies
- `swift-bytes` 0.1.0 — input/output buffer.

### Limitations (out of scope for v0.1)
- **Encoder.** Future v0.2.
- **Streaming decode.** v0.2 alongside the encoder.
- **Custom dictionaries.** v0.3+.
- `Codable` bridging.
