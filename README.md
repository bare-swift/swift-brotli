# swift-brotli

RFC 7932 Brotli decoder — Sendable, Foundation-free.

Part of the [bare-swift](https://github.com/bare-swift) ecosystem.

## Install

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/bare-swift/swift-brotli.git", from: "0.1.0")
```

Then depend on the `Brotli` product:

```swift
.product(name: "Brotli", package: "swift-brotli")
```

## Usage

```swift
import Brotli
import Bytes

let compressed: Bytes = ...   // raw brotli stream
let plain = try Brotli.decode(compressed)
```

For HTTP `Content-Encoding: br` payloads, decode directly with
`Brotli.decode(_:)`. swift-content-encoding v0.3 will add a `br` branch
to its multiplexer in a follow-up release.

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

- `Brotli.decode(_ bytes: Bytes) throws(BrotliError) -> Bytes`
- `BrotliError` typed-throws enum (10 cases).

## Dependencies

- `swift-bytes` 0.1.0 — input/output buffer.

(No `swift-deflate` / `swift-crypto` / other deps — brotli is its own codec.)

## Out of scope for v0.1

- **Encoder.** Per the bare-swift decoder-first staging convention, the encoder lands in a future v0.2.
- **Streaming decode.** v0.1 takes a single full `Bytes` input.
- **Custom dictionaries.** Only the RFC 7932 static dictionary is supported.
- `Codable` bridging.

## Source attribution

The 122 784-byte static dictionary (`Sources/Brotli/Dictionary.swift`), the 121-entry transforms table (`Sources/Brotli/Transforms.swift`), and the four context-mode lookup tables (`Sources/Brotli/ContextMap.swift`) are derived byte-for-byte from Google's brotli reference implementation (MIT-licensed). The algorithmic implementation is a clean-room Swift port of RFC 7932. See [NOTICE](./NOTICE).

## Documentation

Full DocC documentation: <https://bare-swift.github.io/swift-brotli/>

## License

Apache 2.0 with LLVM exception. See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).
