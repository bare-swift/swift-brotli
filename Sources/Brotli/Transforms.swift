// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.
//
// This file is auto-generated. The 121-entry transforms table and the
// 50-entry prefix/suffix string set come from Google brotli's
// c/common/transform.c (MIT-licensed; see NOTICE).
//
// https://github.com/google/brotli/blob/master/c/common/transform.c

/// RFC 7932 § 8 Table 2 — 121 static-dictionary transforms.
///
/// Each transform applies a prefix string, an action on the dictionary
/// word body, and a suffix string. Actions: identity; omitLast{1..9};
/// omitFirst{1..9}; uppercaseFirst / uppercaseAll (limited UTF-8 case-
/// folding); shiftFirst / shiftAll (UTF-8-aware scalar shift, used by
/// transforms 102+).
enum Transforms {
    enum Action: UInt8, Sendable {
        case identity = 0
        case omitLast1 = 1
        case omitLast2 = 2
        case omitLast3 = 3
        case omitLast4 = 4
        case omitLast5 = 5
        case omitLast6 = 6
        case omitLast7 = 7
        case omitLast8 = 8
        case omitLast9 = 9
        case uppercaseFirst = 10
        case uppercaseAll = 11
        case omitFirst1 = 12
        case omitFirst2 = 13
        case omitFirst3 = 14
        case omitFirst4 = 15
        case omitFirst5 = 16
        case omitFirst6 = 17
        case omitFirst7 = 18
        case omitFirst8 = 19
        case omitFirst9 = 20
        case shiftFirst = 21
        case shiftAll = 22
    }

    struct Entry: Sendable {
        let prefix: [UInt8]
        let action: Action
        let suffix: [UInt8]
    }

    /// The 50 prefix/suffix strings referenced by the 121 transforms.
    /// Both prefix and suffix indices share this table.
    static let prefixSuffix: [[UInt8]] = [
        [0x20],
        [0x2C, 0x20],
        [0x20, 0x6F, 0x66, 0x20, 0x74, 0x68, 0x65, 0x20],
        [0x20, 0x6F, 0x66, 0x20],
        [0x73, 0x20],
        [0x2E],
        [0x20, 0x61, 0x6E, 0x64, 0x20],
        [0x20, 0x69, 0x6E, 0x20],
        [0x22],
        [0x20, 0x74, 0x6F, 0x20],
        [0x22, 0x3E],
        [0x0A],
        [0x2E, 0x20],
        [0x5D],
        [0x20, 0x66, 0x6F, 0x72, 0x20],
        [0x20, 0x61, 0x20],
        [0x20, 0x74, 0x68, 0x61, 0x74, 0x20],
        [0x27],
        [0x20, 0x77, 0x69, 0x74, 0x68, 0x20],
        [0x20, 0x66, 0x72, 0x6F, 0x6D, 0x20],
        [0x20, 0x62, 0x79, 0x20],
        [0x28],
        [0x2E, 0x20, 0x54, 0x68, 0x65, 0x20],
        [0x20, 0x6F, 0x6E, 0x20],
        [0x20, 0x61, 0x73, 0x20],
        [0x20, 0x69, 0x73, 0x20],
        [0x69, 0x6E, 0x67, 0x20],
        [0x0A, 0x09],
        [0x3A],
        [0x65, 0x64, 0x20],
        [0x3D, 0x22],
        [0x20, 0x61, 0x74, 0x20],
        [0x6C, 0x79, 0x20],
        [0x2C],
        [0x3D, 0x27],
        [0x2E, 0x63, 0x6F, 0x6D, 0x2F],
        [0x2E, 0x20, 0x54, 0x68, 0x69, 0x73, 0x20],
        [0x20, 0x6E, 0x6F, 0x74, 0x20],
        [0x65, 0x72, 0x20],
        [0x61, 0x6C, 0x20],
        [0x66, 0x75, 0x6C, 0x20],
        [0x69, 0x76, 0x65, 0x20],
        [0x6C, 0x65, 0x73, 0x73, 0x20],
        [0x65, 0x73, 0x74, 0x20],
        [0x69, 0x7A, 0x65, 0x20],
        [0xC2, 0xA0],
        [0x6F, 0x75, 0x73, 0x20],
        [0x20, 0x74, 0x68, 0x65, 0x20],
        [0x65, 0x20],
        [],
    ]

    /// The 121 (prefix_index, action, suffix_index) triples.
    static let table: [(prefixIdx: Int, action: Action, suffixIdx: Int)] = [
        (49, .identity, 49),
        (49, .identity, 0),
        (0, .identity, 0),
        (49, .omitFirst1, 49),
        (49, .uppercaseFirst, 0),
        (49, .identity, 47),
        (0, .identity, 49),
        (4, .identity, 0),
        (49, .identity, 3),
        (49, .uppercaseFirst, 49),
        (49, .identity, 6),
        (49, .omitFirst2, 49),
        (49, .omitLast1, 49),
        (1, .identity, 0),
        (49, .identity, 1),
        (0, .uppercaseFirst, 0),
        (49, .identity, 7),
        (49, .identity, 9),
        (48, .identity, 0),
        (49, .identity, 8),
        (49, .identity, 5),
        (49, .identity, 10),
        (49, .identity, 11),
        (49, .omitLast3, 49),
        (49, .identity, 13),
        (49, .identity, 14),
        (49, .omitFirst3, 49),
        (49, .omitLast2, 49),
        (49, .identity, 15),
        (49, .identity, 16),
        (0, .uppercaseFirst, 49),
        (49, .identity, 12),
        (5, .identity, 49),
        (0, .identity, 1),
        (49, .omitFirst4, 49),
        (49, .identity, 18),
        (49, .identity, 17),
        (49, .identity, 19),
        (49, .identity, 20),
        (49, .omitFirst5, 49),
        (49, .omitFirst6, 49),
        (47, .identity, 49),
        (49, .omitLast4, 49),
        (49, .identity, 22),
        (49, .uppercaseAll, 49),
        (49, .identity, 23),
        (49, .identity, 24),
        (49, .identity, 25),
        (49, .omitLast7, 49),
        (49, .omitLast1, 26),
        (49, .identity, 27),
        (49, .identity, 28),
        (0, .identity, 12),
        (49, .identity, 29),
        (49, .omitFirst9, 49),
        (49, .omitFirst7, 49),
        (49, .omitLast6, 49),
        (49, .identity, 21),
        (49, .uppercaseFirst, 1),
        (49, .omitLast8, 49),
        (49, .identity, 31),
        (49, .identity, 32),
        (47, .identity, 3),
        (49, .omitLast5, 49),
        (49, .omitLast9, 49),
        (0, .uppercaseFirst, 1),
        (49, .uppercaseFirst, 8),
        (5, .identity, 21),
        (49, .uppercaseAll, 0),
        (49, .uppercaseFirst, 10),
        (49, .identity, 30),
        (0, .identity, 5),
        (35, .identity, 49),
        (47, .identity, 2),
        (49, .uppercaseFirst, 17),
        (49, .identity, 36),
        (49, .identity, 33),
        (5, .identity, 0),
        (49, .uppercaseFirst, 21),
        (49, .uppercaseFirst, 5),
        (49, .identity, 37),
        (0, .identity, 30),
        (49, .identity, 38),
        (0, .uppercaseAll, 0),
        (49, .identity, 39),
        (0, .uppercaseAll, 49),
        (49, .identity, 34),
        (49, .uppercaseAll, 8),
        (49, .uppercaseFirst, 12),
        (0, .identity, 21),
        (49, .identity, 40),
        (0, .uppercaseFirst, 12),
        (49, .identity, 41),
        (49, .identity, 42),
        (49, .uppercaseAll, 17),
        (49, .identity, 43),
        (0, .uppercaseFirst, 5),
        (49, .uppercaseAll, 10),
        (0, .identity, 34),
        (49, .uppercaseFirst, 33),
        (49, .identity, 44),
        (49, .uppercaseAll, 5),
        (45, .identity, 49),
        (0, .identity, 33),
        (49, .uppercaseFirst, 30),
        (49, .uppercaseAll, 30),
        (49, .identity, 46),
        (49, .uppercaseAll, 1),
        (49, .uppercaseFirst, 34),
        (0, .uppercaseFirst, 33),
        (0, .uppercaseAll, 30),
        (0, .uppercaseAll, 1),
        (49, .uppercaseAll, 33),
        (49, .uppercaseAll, 21),
        (49, .uppercaseAll, 12),
        (0, .uppercaseAll, 5),
        (49, .uppercaseAll, 34),
        (0, .uppercaseAll, 12),
        (0, .uppercaseFirst, 30),
        (0, .uppercaseAll, 34),
        (0, .uppercaseFirst, 34),
    ]

    /// Apply transform `index` (0..120) to a slice of the dictionary.
    /// Returns the transformed byte sequence per RFC 7932 § 8.
    static func apply(_ index: Int, to word: ArraySlice<UInt8>) throws(BrotliError) -> [UInt8] {
        guard index >= 0 && index < table.count else { throw .invalidTransform }
        let (prefixIdx, action, suffixIdx) = table[index]
        var out: [UInt8] = []
        out.reserveCapacity(prefixSuffix[prefixIdx].count + word.count + prefixSuffix[suffixIdx].count)
        out.append(contentsOf: prefixSuffix[prefixIdx])
        var body = Array(word)
        switch action {
        case .identity: break
        case .omitLast1: if body.count >= 1 { body.removeLast(1) }
        case .omitLast2: if body.count >= 2 { body.removeLast(2) }
        case .omitLast3: if body.count >= 3 { body.removeLast(3) }
        case .omitLast4: if body.count >= 4 { body.removeLast(4) }
        case .omitLast5: if body.count >= 5 { body.removeLast(5) }
        case .omitLast6: if body.count >= 6 { body.removeLast(6) }
        case .omitLast7: if body.count >= 7 { body.removeLast(7) }
        case .omitLast8: if body.count >= 8 { body.removeLast(8) }
        case .omitLast9: if body.count >= 9 { body.removeLast(9) }
        case .omitFirst1: if body.count >= 1 { body.removeFirst(1) }
        case .omitFirst2: if body.count >= 2 { body.removeFirst(2) }
        case .omitFirst3: if body.count >= 3 { body.removeFirst(3) }
        case .omitFirst4: if body.count >= 4 { body.removeFirst(4) }
        case .omitFirst5: if body.count >= 5 { body.removeFirst(5) }
        case .omitFirst6: if body.count >= 6 { body.removeFirst(6) }
        case .omitFirst7: if body.count >= 7 { body.removeFirst(7) }
        case .omitFirst8: if body.count >= 8 { body.removeFirst(8) }
        case .omitFirst9: if body.count >= 9 { body.removeFirst(9) }
        case .uppercaseFirst:
            uppercaseFirst(&body)
        case .uppercaseAll:
            uppercaseAll(&body)
        case .shiftFirst, .shiftAll:
            // RFC 7932 § 8 reserves shift transforms but the canonical
            // 121-transform table does not use them; only v0.2+ extension
            // tables would. v0.1 throws if encountered.
            throw .invalidTransform
        }
        out.append(contentsOf: body)
        out.append(contentsOf: prefixSuffix[suffixIdx])
        return out
    }

    /// Uppercase the first 'character' of `body`, treating it as UTF-8.
    /// Per Brotli's reference: ASCII a-z → A-Z; 2-byte UTF-8 lead → xor bit
    /// 5 of trailing byte; 3+ byte → xor bit 0..2 of third byte.
    private static func uppercaseFirst(_ body: inout [UInt8]) {
        _ = uppercaseStep(&body, offset: 0)
    }

    /// Uppercase every 'character' (UTF-8 sense) in `body`.
    private static func uppercaseAll(_ body: inout [UInt8]) {
        var i = 0
        while i < body.count {
            let step = uppercaseStep(&body, offset: i)
            i += step
        }
    }

    /// Uppercase the UTF-8 character starting at `body[offset]`; returns
    /// the number of bytes consumed (1, 2, or 3).
    private static func uppercaseStep(_ body: inout [UInt8], offset: Int) -> Int {
        guard offset < body.count else { return 1 }
        let b = body[offset]
        if b < 0xC0 {
            if b >= 0x61 && b <= 0x7A {
                body[offset] = b ^ 0x20
            }
            return 1
        }
        if b < 0xE0 {
            if offset + 1 < body.count {
                body[offset + 1] = body[offset + 1] ^ 0x20
            }
            return 2
        }
        if offset + 2 < body.count {
            body[offset + 2] = body[offset + 2] ^ 0x05
        }
        return 3
    }
}
