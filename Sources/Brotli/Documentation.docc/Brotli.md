# ``Brotli``

RFC 7932 Brotli codec — decoder (v0.1) + one-shot encoder (v0.2) + streaming encoder (v0.3) + streaming decoder (v0.5) + true memory-streaming decode (v0.6). Sendable, Foundation-free.

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

**Streaming compress** (since v0.3):

```swift
var encoder = try Brotli.Streaming.Encoder(quality: .default)
encoder.update(chunk1)
encoder.update(chunk2)
let compressed = try encoder.finish()
```

Each `update(_:)` emits one Brotli metablock; `finish()` finalizes the
stream. See ``Brotli/Streaming/Encoder`` for semantics around chunk
boundaries, oversized chunks (>16 MiB are split internally), and
finished-encoder behavior. v0.3 does not carry LZ77 match search across
chunk boundaries — matches that span chunks are not found (deferred to
v0.4).

**Streaming decompress** (since v0.5):

```swift
var decoder = Brotli.Streaming.Decoder()
decoder.update(compressedChunk1)
decoder.update(compressedChunk2)
let plain = try decoder.finish()
```

The v0.5 decoder buffers all compressed input internally and runs
`Brotli.decode(_:)` one-shot at `finish()` — honest scope under
limitation. True memory-streaming inflate (state-machine refactor of
the internal `Decoder`) is deferred to v0.6+; v0.5 ships the
streaming-symmetric API surface for adopter composition. See
``Brotli/Streaming/Decoder``.

For HTTP `Content-Encoding: br`, swift-content-encoding v0.3+ wires the
decode side; the encode side lands in v0.4.

Per [RFC-0015](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0015-phase-10-anchor-brotli-decoder.md),
[RFC-0017](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0017-phase-12-anchor-brotli-encoder.md),
and [RFC-0027](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0027-phase-22-anchor-swift-brotli-v0.3-streaming-encoder.md),
v0.1 shipped decoding only; v0.2 added one-shot encoding; v0.3 adds
streaming encoding.

## Topics

### Decode

- ``Brotli/decode(_:)``

### Compress

- ``Brotli/compress(_:quality:)``
- ``Brotli/Quality``
- ``Brotli/maxInputSize``

### Streaming compress (v0.3+)

- ``Brotli/Streaming``
- ``Brotli/Streaming/Encoder``

### Streaming decompress (v0.5+)

- ``Brotli/Streaming/Decoder``

### Errors

- ``BrotliError``
