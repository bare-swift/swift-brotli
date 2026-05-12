# ``Brotli``

RFC 7932 Brotli decoder — Sendable, Foundation-free.

## Overview

`Brotli.decode(_:)` strips the RFC 7932 stream header, runs the
meta-block decode loop, and returns the decompressed `Bytes`. All four
literal context modes, all 121 static-dictionary transforms, the full
122 784-byte static dictionary, and the § 4 distance ring buffer are
implemented.

```swift
import Brotli
import Bytes

let compressed: Bytes = ...   // raw brotli stream
let plain = try Brotli.decode(compressed)
```

For HTTP `Content-Encoding: br` payloads, decode directly with this
package — swift-content-encoding v0.3 will add a `br` multiplex branch
in a follow-up release.

Per [RFC-0015](https://github.com/bare-swift/bare-swift/blob/main/rfcs/0015-phase-10-anchor-brotli-decoder.md),
**v0.1 ships decoding only**. The encoder lands in a future minor release.

## Topics

### Decode

- ``Brotli/decode(_:)``

### Errors

- ``BrotliError``
