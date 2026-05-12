// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// RFC 7932 § 9.2 meta-block header.
///
/// Encodes ISLAST, ISLASTEMPTY, MNIBBLES (4/5/6), MLEN (the decoded
/// output length in bytes), MSKIPBYTES (for empty meta-blocks carrying
/// only metadata), and ISUNCOMPRESSED. Reading proceeds bit-by-bit;
/// some fields are conditional on prior fields.
struct MetaBlockHeader {
    /// `true` when this is the last meta-block in the stream.
    var isLast: Bool
    /// `true` when this is the "last and empty" final marker
    /// (ISLAST=1, ISLASTEMPTY=1). When set, the stream ends here.
    var isLastEmpty: Bool
    /// Decoded payload length in bytes. `0` for empty / skip meta-blocks.
    var mlen: Int
    /// `true` when the meta-block carries an uncompressed payload (raw
    /// bytes after byte-alignment). Only meaningful when `!isLastEmpty`.
    var isUncompressed: Bool

    static func read(_ r: inout BitReader) throws(BrotliError) -> MetaBlockHeader {
        let isLast = try r.readBit() == 1
        if isLast {
            let isLastEmpty = try r.readBit() == 1
            if isLastEmpty {
                return MetaBlockHeader(isLast: true, isLastEmpty: true, mlen: 0, isUncompressed: false)
            }
        }
        // MNIBBLES code: 2 bits. 00→4, 01→5, 10→6, 11→ MSKIPBYTES path.
        let mnibblesCode = try r.readBits(2)
        if mnibblesCode == 3 {
            // Empty / skip meta-block. § 9.2:
            //   read MSKIPBYTES (2 bits)
            //   if MSKIPBYTES == 0: this is an empty meta-block (no payload);
            //                       read a reserved bit (must be 0), align to byte.
            //   else: read MSKIPLEN-1 in (8 * MSKIPBYTES) bits, then align,
            //         then skip MSKIPLEN bytes (these are user-meta-data).
            let mskipbytes = try r.readBits(2)
            if mskipbytes == 0 {
                let reserved = try r.readBit()
                if reserved != 0 { throw .invalidMetaBlockHeader }
                r.alignToByte()
                return MetaBlockHeader(isLast: false, isLastEmpty: false, mlen: 0, isUncompressed: false)
            }
            let bits = 8 * Int(mskipbytes)
            // Reject the encoding where the high byte of MSKIPLEN-1 is 0
            // (canonical Brotli forbids it because that would be a shorter
            // encoding using fewer MSKIPBYTES).
            let mskipMinus1 = try r.readBits(bits)
            if bits > 8 {
                let highByte = (mskipMinus1 >> (bits - 8)) & 0xFF
                if highByte == 0 { throw .invalidMetaBlockHeader }
            }
            let mskiplen = Int(mskipMinus1) + 1
            r.alignToByte()
            _ = try r.readBytes(mskiplen)
            return MetaBlockHeader(isLast: false, isLastEmpty: false, mlen: 0, isUncompressed: false)
        }
        let mnibbles = Int(mnibblesCode) + 4  // 4, 5, or 6
        let mlenMinus1 = try r.readBits(4 * mnibbles)
        // Reject the encoding where the high nibble is 0 for mnibbles in {5, 6}
        // (canonical Brotli forbids it because that would be a shorter encoding).
        if mnibbles > 4 {
            let highNibble = (mlenMinus1 >> (4 * (mnibbles - 1))) & 0xF
            if highNibble == 0 { throw .invalidMetaBlockHeader }
        }
        let mlen = Int(mlenMinus1) + 1
        var isUncompressed = false
        if !isLast {
            isUncompressed = try r.readBit() == 1
        }
        return MetaBlockHeader(isLast: isLast, isLastEmpty: false, mlen: mlen, isUncompressed: isUncompressed)
    }
}
