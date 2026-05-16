# swift-brotli

RFC 7932 Brotli codec — decoder (v0.1) + one-shot encoder (v0.2) + streaming encoder (v0.3). Sendable, Foundation-free.

Part of the [bare-swift](https://github.com/bare-swift) ecosystem.

## Install

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/bare-swift/swift-brotli.git", from: "0.3.0")
```

Then depend on the `Brotli` product:

```swift
.product(name: "Brotli", package: "swift-brotli")
```

## Usage

```swift
import Brotli
import Bytes

// Decode (v0.1):
let compressed: Bytes = ...
let plain = try Brotli.decode(compressed)

// Compress (v0.2):
let input: Bytes = ...
let encoded = try Brotli.compress(input)
let smaller = try Brotli.compress(input, quality: .smallest)
let fast    = try Brotli.compress(input, quality: .fastest)
```

## Streaming (v0.3+)

```swift
import Brotli
import Bytes

var encoder = try Brotli.Streaming.Encoder(quality: .default)
encoder.update(chunk1)
encoder.update(chunk2)
let compressed = try encoder.finish()
let plain = try Brotli.decode(compressed)
// plain == chunk1 + chunk2
```

Each `update(_:)` emits one Brotli metablock per chunk. Empty chunks are
no-ops; chunks larger than 16 MiB split internally into multiple
metablocks. `finish()` emits a terminator metablock and returns the full
stream. After `finish()` the encoder is consumed — further `update(_:)`
calls are silent no-ops; another `finish()` throws `encoderFinished`.

`Brotli.Streaming.Encoder` does not carry LZ77 match search across chunk
boundaries in v0.3. Matches that span chunks are not found, slightly
hurting compression ratio compared to `Brotli.compress(_:)` one-shot.
This is a v0.4 deferral.

For HTTP `Content-Encoding: br`, swift-content-encoding v0.3+ wires the
decode side; the encode side will land in v0.4.

## Scope

`swift-brotli` v0.1 implements RFC 7932 single-shot decompression:

- Stream parser (WBITS 10..24) per § 9.1.
- Meta-block parser (compressed / uncompressed / empty + multi-meta-block) per § 9.2.
- Three prefix-code alphabets per meta-block (literal, insert-and-copy, distance), each partitioned by block type per § 6.
- All four literal context modes (LSB6, MSB6, UTF8, Signed) per § 7.1.
- § 7.3 context maps with RLE for zero runs and optional Inverse Move-to-Front.
- § 4 distance decoder with last-distance ring buffer (initialized to `[16, 15, 11, 4]` at stream start, carried across meta-blocks).
- § 8 static dictionary (122 784 bytes) + all 121 transforms.
- Output capped at 64 MiB to prevent decompression bombs.

Public API:

- `Brotli.decode(_ bytes: Bytes) throws(BrotliError) -> Bytes` (v0.1)
- `Brotli.compress(_ bytes: Bytes, quality: Quality = .default) throws(BrotliError) -> Bytes` (v0.2)
- `Brotli.Streaming.Encoder(quality:)` + `update(_:)` + `finish() throws(BrotliError) -> Bytes` (v0.3)
- `Brotli.Quality` enum: `.fastest` / `.fast` / `.default` / `.balanced` / `.smallest` / `.level(Int)`.
- `BrotliError` typed-throws enum (13 cases).

## Dependencies

- `swift-bytes` 0.1.0 — input/output buffer.

(No `swift-deflate` / `swift-crypto` / other deps — brotli is its own codec.)

## v0.2 encoder scope

The v0.2 encoder produces **valid** brotli streams that round-trip via this
package's decoder and the reference `brotli` CLI — but it does NOT match
the reference encoder's compression ratio. Quality affects only
match-search depth (chain pointers visited + max distance window);
everything else is constant across quality tiers.

**Explicit non-goals for v0.2** (deferred to v0.3+):

- **Streaming encoder.** One-shot only; inputs > 16 MiB-1 throw `.inputTooLarge`.
- **Static-dictionary search.** Quality-11 reference feature; not implemented.
- **Multi-metablock partitioning.** v0.2 emits one metablock per `compress()`.
- **Advanced literal-context modes.** NTREESL=1 (single tree).
- **Block-switch commands.** NBLTYPES{L,I,D}=1.
- **Last-4-distance ring-buffer shortcuts.** v0.2 emits direct distance codes only.

## Out of scope (v0.1 + v0.2)

- **Streaming decode.** v0.1/v0.2 take a single full `Bytes` input.
- **Custom dictionaries.** Only the RFC 7932 static dictionary is supported.
- `Codable` bridging.

## Source attribution

The 122 784-byte static dictionary (`Sources/Brotli/Dictionary.swift`), the 121-entry transforms table (`Sources/Brotli/Transforms.swift`), and the four context-mode lookup tables (`Sources/Brotli/ContextMap.swift`) are derived byte-for-byte from Google's brotli reference implementation (MIT-licensed). The algorithmic implementation is a clean-room Swift port of RFC 7932. See [NOTICE](./NOTICE).

## Documentation

Full DocC documentation: <https://bare-swift.github.io/swift-brotli/>

## License

Apache 2.0 with LLVM exception. See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).
