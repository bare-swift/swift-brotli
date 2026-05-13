# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.2.0] — 2026-05-13

### Added
- `Brotli.compress(_ bytes: Bytes, quality: Quality = .default) throws(BrotliError) -> Bytes` — single-shot RFC 7932 encoder.
- `Brotli.Quality` nested enum: `.fastest` (level 0) / `.fast` (4) / `.default` (6) / `.balanced` (9) / `.smallest` (11) / `.level(Int)` for explicit numeric levels in `0...11`.
- `BrotliError.inputTooLarge` (input exceeds 16 MiB - 1) and `.qualityOutOfRange` (`Quality.level(n)` with `n < 0 || n > 11`).
- `Brotli.maxInputSize` constant (= 16 MiB - 1) — the encoder's one-shot cap.
- 8 new internal files: `BitWriter`, `Encoder`, `MatchFinder`, `EncoderCommand`, `HuffmanBuilder`, `PrefixCodeEmitter`, `EncoderMetaBlock` + the `Quality` enum nested in `Brotli`.
- ~50 new tests across 8 suites covering BitWriter (LSB-first wire format), HuffmanBuilder (package-merge length-limited canonical Huffman + RFC 1951 § 3.2.2 canonical-codes with `bl_count[0]` reset), PrefixCodeEmitter (simple + complex form round-trip through v0.1 reader), EncoderCommand (insert/copy/distance brackets + combined symbol formula), MatchFinder (literal-only quality 0 + LZ77 chain match-finding), end-to-end round-trip matrix (5 quality levels × 7 input shapes), error paths, and compression sanity.

### v0.2 encoder scope (explicit non-goals — deferred to v0.3+)
- **Streaming encoder API.** v0.2 is one-shot only.
- **Static-dictionary search.** Quality-11 reference feature; the static dictionary stays loaded only for the v0.1 decoder.
- **Multi-metablock partitioning.** v0.2 emits one metablock per `compress()`.
- **Advanced literal-context modes (NTREESL > 1).** v0.2 uses NTREESL=1 (single literal Huffman tree).
- **Block-switch commands (NBLTYPES{L,I,D} > 1).**
- **Last-4-distance ring-buffer shortcuts.** v0.2 emits direct distance codes only.

Quality affects only match-search depth (chain pointers visited + max-distance window); everything else is constant across quality tiers. Output is **valid** brotli (round-trips via v0.1 decoder and the reference `brotli` CLI) but does NOT match the reference encoder's compression ratio.

### Unchanged
- v0.1 decoder API and behavior. All v0.1 consumers continue to work unchanged.

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
