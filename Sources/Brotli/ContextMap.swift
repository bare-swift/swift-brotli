// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// Copyright (c) 2026 The bare-swift Project Authors.

/// RFC 7932 § 7.1 literal context modes.
///
/// Four modes (CM0..CM3) compute a 6-bit context ID from the last two
/// output bytes `(p1, p2)`. The context ID is used to look up which
/// literal-prefix-code tree to use for the next literal.
///
/// CM0 (LSB6):   low 6 bits of p1.
/// CM1 (MSB6):   top 6 bits of p1.
/// CM2 (UTF8):   joint Lut0[p1] | Lut1[p2]; tables in § 7.1.
/// CM3 (Signed): joint Lut0[p1] | Lut1[p2]; tables in § 7.1.
enum ContextMode: UInt8, Sendable {
    case lsb6 = 0
    case msb6 = 1
    case utf8 = 2
    case signed = 3

    /// Compute the 6-bit context ID for the next literal.
    ///
    /// **Stage B:** the UTF8 and Signed branches require pasting the
    /// 256-entry LUT0 / LUT1 tables from RFC 7932 § 7.1 into the
    /// constants below. The LSB6 and MSB6 branches are complete.
    func contextID(p1: UInt8, p2: UInt8) -> Int {
        switch self {
        case .lsb6:
            return Int(p1 & 0x3F)
        case .msb6:
            return Int(p1) >> 2
        case .utf8:
            return Int(ContextMap.lut0_utf8[Int(p1)]) | Int(ContextMap.lut1_utf8[Int(p2)])
        case .signed:
            return Int(ContextMap.lut0_signed[Int(p1)]) | Int(ContextMap.lut1_signed[Int(p2)])
        }
    }
}

/// Static lookup tables for CM2 (UTF8) and CM3 (Signed) per RFC 7932 § 7.1.
///
/// **Stage B handoff.** The four LUTs below are placeholders sized to
/// 256 entries each. The executor pastes the actual values from RFC
/// 7932 § 7.1's tables.
enum ContextMap {
    /// LUT0 for CM2 (UTF8). 256 entries; values are multiples of 4 in
    /// {0, 4, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60}.
    /// Stage B: replace with RFC 7932 § 7.1 LUT0_UTF8 table.
    static let lut0_utf8: [UInt8] = Array(repeating: 0, count: 256)

    /// LUT1 for CM2 (UTF8). 256 entries; values are 0..3.
    /// Stage B: replace with RFC 7932 § 7.1 LUT1_UTF8 table.
    static let lut1_utf8: [UInt8] = Array(repeating: 0, count: 256)

    /// LUT0 for CM3 (Signed). 256 entries.
    /// Stage B: replace with RFC 7932 § 7.1 LUT0_SIGNED table.
    static let lut0_signed: [UInt8] = Array(repeating: 0, count: 256)

    /// LUT1 for CM3 (Signed). 256 entries.
    /// Stage B: replace with RFC 7932 § 7.1 LUT1_SIGNED table.
    static let lut1_signed: [UInt8] = Array(repeating: 0, count: 256)
}
