# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.6.0] — 2026-05-18

### Added
- **`Brotli.Streaming.Decoder` is now a true memory-streaming inflater.** The internal implementation switches from v0.5's buffering-wrap (accumulate input then run `Brotli.decode(_:)` one-shot at `finish()`) to a new state-machine `StreamingDecoder` that consumes input and yields decoded bytes incrementally per `update(_:)` call. The reader is checkpointed before each atomic Huffman-symbol read; truncated input rewinds to the checkpoint and pauses cleanly until the next `update(_:)` provides more bytes. Per-symbol state (insertLen / copyLen / useDistance / emitted-literal-count) lives in struct fields and survives `update(_:)` boundaries.
- 5 new tests verifying true incremental yield: byte-by-byte feed equals one-shot (small payload), byte-by-byte feed with repeated pangram (exercises match codes), split-mid-stream at varied positions, 1 MiB payload byte-by-byte (exercises multi-metablock + persistent distance ring buffer), and malformed-input error captured during `update(_:)` then surfaced at `finish()`.

### Honest-scope-under-limitation **RESOLVED at the codec-tier brotli boundary**
v0.5 shipped the streaming-symmetric API surface ahead of true memory-streaming as an honest deferral. v0.6 resolves the deferral via state-machine refactor:
- **Public API surface unchanged.** `Brotli.Streaming.Decoder.init() / update(_:) / finish() throws(BrotliError) -> Bytes` byte-for-byte preserved.
- **All v0.5 tests continue to pass** without modification (140 → 145 with 5 new v0.6 tests).
- **Adopters require zero migration.** The implementation upgrade is internal.

This completes the **codec-tier true-memory-streaming story** end-to-end (Phase 30 → 31 → 32 → 33 → 34 → 35 → 36). After v0.6, the entire 6-instance honest-scope-under-limitation pattern from Phases 25-33 is RESOLVED.

### Internal changes
- `BitReader`: `bytes` is now mutable (`var ContiguousArray<UInt8>`). New `append(_:)`, `Snapshot`, `snapshot()`, `restore(_:)`, `availableBytesAligned()`. v0.1-v0.5 one-shot `Brotli.decode(_:)` constructor + read methods unchanged behaviorally.
- New file `StreamingDecoder.swift` (~390 LOC): state-machine driver with `Phase` enum (`awaitingStreamHeader` / `awaitingMetaBlockHeader` / `inUncompressed` / `awaitingMetaBlockTrees` / `inMetaBlockBody` / `done`) and nested `BodyState` + `BodySubPhase` (`awaitIC` / `emittingLiterals` / `awaitDistance`). Snapshots taken at every atomic-read boundary; truncation rewinds cleanly. Used only by `Streaming.Decoder`; one-shot `Decoder.swift` retained unchanged for `Brotli.decode(_:)`.
- `Streaming.Decoder`: internal `buffer: ContiguousArray<UInt8>` replaced with `inflater: StreamingDecoder` + `pendingError: BrotliError?`. `update(_:)` invokes the state machine and captures real decode errors into `pendingError`; `finish()` rethrows the captured error or asserts `phase == .done`.

### Migration (v0.5 → v0.6)
- **Additive only — non-breaking.** All v0.1-v0.5 APIs unchanged.
- `Brotli.decode(_:)` one-shot continues to produce byte-identical output.
- `Brotli.Streaming.Encoder` (v0.3+) and `drain()` (v0.4) unchanged.
- `BrotliError` cases unchanged.

### Downstream propagation (informational, not landed here)
- swift-content-encoding v0.9: dep bump brotli 0.5 → 0.6 replaces v0.8's partial-propagation acknowledgment with uniform true-memory-streaming for all coding chains (Phase 37+ candidate).

### Phase 36
- Tranche 36A of [RFC-0041](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0041-phase-36-anchor-swift-brotli-v0.6-true-memory-streaming.md). Closes the codec-tier true-memory-streaming story entirely. Applies Phase 34's four codified sub-patterns (snapshot-and-restore, real-error-capture+rethrow, two-track coexistence, early-out-for-trivially-completable) at higher state-machine complexity.

## [0.5.0] — 2026-05-17

### Added
- **`Brotli.Streaming.Decoder`** — Sendable value-type streaming decoder mirroring `Brotli.Streaming.Encoder`'s API shape: `init()` / `update(_ chunk: Bytes)` / `finish() throws(BrotliError) -> Bytes`. Feed compressed input via `update(_:)`, call `finish()` to receive the decompressed output.
- **`BrotliError.decoderFinished`** — thrown when `finish()` is called twice on the same decoder.
- 17 new tests covering single-chunk and multi-chunk decode round-trips via the v0.2 one-shot encoder, tiny 1-byte chunks, 70 KiB payloads, `.fastest` / `.smallest` quality coverage, truncated-input errors, double-finish, update-after-finish no-op, empty stream, single-byte payload, and equivalence with `Brotli.decode(_:)` one-shot.

### Honest scope under limitation (v0.5)
The v0.5 decoder **buffers all compressed input bytes internally and runs `Brotli.decode(_:)` one-shot at `finish()`**. The decoded output is not yielded incrementally during `update(_:)`. True memory-streaming brotli decode requires a state-machine refactor of the internal `Decoder` plus supporting helpers (`MetaBlockHeader`, `OutputBuffer`, `ContextMap`, `PrefixCode`) — deferred to v0.6+ on adopter demand. v0.5 ships the **streaming-symmetric API surface** today so swift-content-encoding v0.7 streaming-decode wiring and downstream HTTP middleware can adopt a stable decoder shape without waiting for the underlying refactor.

This matches the Phase 30 (deflate v0.5) + Phase 31 (gzip + zlib v0.5) honest-scope-under-limitation pattern.

### Migration (v0.4 → v0.5)
- **Additive only — non-breaking.** All v0.1-v0.4 APIs unchanged.
- `Brotli.decode(_:)` continues to produce byte-identical output.
- `Brotli.compress(_:quality:)`, `Brotli.Streaming.Encoder`, and `drain()` are unchanged.
- New error case `BrotliError.decoderFinished` is additive (no exhaustive-switch callers exist outside this package; callers using `catch BrotliError.X` patterns are unaffected).

### Phase 32
- Tranche 32A of [RFC-0037](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0037-phase-32-anchor-swift-brotli-v0.5-streaming-inflate.md). Completes codec-tier streaming-decode (after deflate + gzip + zlib in Phases 30-31).

## [0.4.0] — 2026-05-17

### Added
- **`Brotli.Streaming.Encoder.drain() -> Bytes`** — returns the byte-aligned portion of the accumulated stream so far, resetting the internal byte buffer. The encoder remains in the open state; subsequent `update(_:)` and `finish()` calls produce the remainder. Concatenating all `drain()` returns with the final `finish()` return produces the **same bytes** as a single `finish()` call would have produced (byte-for-byte equality). Does NOT byte-align (partial-byte buffer survives) and does NOT emit a terminator. Silent no-op (returns empty `Bytes`) after `finish()`.
- 5 new tests covering drain semantics, drain+finish round-trip, multiple-drain round-trip, drain-after-finish no-op, and byte-equality with non-draining stream.

### Use case
Multi-coding HTTP `Content-Encoding` streaming via swift-content-encoding v0.6 (Phase 28+). Without `drain()`, multi-coding chains would require buffering each encoder's full output before feeding it to the next, defeating the streaming purpose. `drain()` lets HTTP-layer orchestration pipe bytes through cascaded encoders incrementally.

### Migration (v0.3 → v0.4)
- **Additive only — non-breaking.** All v0.3 APIs unchanged.
- Existing v0.3 streams (no `drain()` calls) produce byte-identical output to v0.3.
- `BrotliError` cases unchanged.

### Phase 27
- Tranche 27A of [RFC-0032](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0032-phase-27-anchor-codec-tier-v0.4-drain-sweep.md). Coordinated 4-tranche codec-tier v0.4 sweep adding `drain()` to brotli + deflate + gzip + zlib streaming encoders.

## [0.3.0] — 2026-05-16

### Added
- **Streaming encoder** — `Brotli.Streaming.Encoder` struct with `init(quality:)` / `update(_:)` / `finish()`. Each `update(_:)` emits one Brotli metablock per chunk (or N metablocks if a chunk exceeds 16 MiB). `finish()` emits a 2-bit terminator metablock and returns accumulated bytes.
- `Brotli.Streaming` public namespace enum.
- `BrotliError.encoderFinished` — thrown when `finish()` is called on an already-finished encoder.
- 16 new tests covering round-trip (empty, single chunk, two chunks, 100 tiny chunks, ≥16 MiB chunks), quality coverage (`.fastest`, `.smallest`), and error/edge cases (invalid quality at init, double-finish, update-after-finish no-op).

### Dependencies
- No new dependencies. swift-bytes already in v0.1.

### Stream-format notes
- Streaming output is **valid Brotli** that decodes via the same `Brotli.decode(_:)` v0.1 API.
- Empty stream output (`Brotli.Streaming.Encoder()` with no `update` calls + `finish()`) is **byte-equal** to `Brotli.compress(Bytes())`. Regression-tested.
- Single-update streaming output is **not** byte-equal to `Brotli.compress(_:)` one-shot output (differs by ~1-3 bits due to extra ISUNCOMPRESSED bit + terminator metablock). Decoded equality holds.
- No window carry across chunks in v0.3. LZ77 match search is per-chunk; matches across chunk boundaries are not found. Deferred to v0.4 for compression-ratio improvement.

### Migration (v0.2 → v0.3)
- **Additive only — non-breaking.** All v0.2 APIs unchanged.
- `Brotli.compress(_:quality:)` continues to emit byte-equal output to v0.2 (regression-tested via existing v0.2 round-trip tests).
- `Brotli.decode(_:)` unchanged from v0.1.
- `Brotli.Quality` unchanged.
- `BrotliError` adds 1 new case (additive; existing cases unchanged).

### Out of scope (deferred to v0.4+)
- Window carry across chunks (LZ77 across chunk boundaries — ratio improvement).
- Per-chunk explicit flush API.
- `reset()` for encoder reuse.
- Streaming decode.
- Static-dictionary search.
- Multi-threaded streaming.

### Phase 22
- Tranche 22A of [RFC-0027](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0027-phase-22-anchor-swift-brotli-v0.3-streaming-encoder.md). Closes the longest-standing codec-tier deferral (9 consecutive gates since Phase 12).

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
