# ``Brotli``

RFC 7932 Brotli codec — decoder (v0.1) + encoder (v0.2). Sendable, Foundation-free.

## Overview

**Decode** (since v0.1):

```swift
import Brotli
import Bytes

let compressed: Bytes = ...
let plain = try Brotli.decode(compressed)
```

`Brotli.decode(_:)` strips the RFC 7932 stream header, runs the meta-block
decode loop, and returns the decompressed `Bytes`. All four literal
context modes, all 121 static-dictionary transforms, the full
122 784-byte static dictionary, and the § 4 distance ring buffer are
implemented.

**Compress** (since v0.2):

```swift
let input: Bytes = ...
let encoded = try Brotli.compress(input)
let smaller = try Brotli.compress(input, quality: .smallest)
```

`Brotli.compress(_:quality:)` produces a valid brotli stream that
round-trips via this package's decoder and the reference `brotli` CLI.
v0.2 is one-shot (inputs > 16 MiB-1 throw `BrotliError.inputTooLarge`)
and uses a single metablock with NTREES{L,I,D}=1 / NPOSTFIX=0 /
NDIRECT=0. Quality affects match-search depth only; v0.2 does NOT match
the reference encoder's compression ratio.

For HTTP `Content-Encoding: br`, swift-content-encoding v0.3+ wires the
decode side; the encode side lands in v0.4.

Per [RFC-0015](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0015-phase-10-anchor-brotli-decoder.md)
and [RFC-0017](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0017-phase-12-anchor-brotli-encoder.md),
v0.1 shipped decoding only; v0.2 adds encoding.

## Topics

### Decode

- ``Brotli/decode(_:)``

### Compress

- ``Brotli/compress(_:quality:)``
- ``Brotli/Quality``
- ``Brotli/maxInputSize``

### Errors

- ``BrotliError``
