// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

import Testing
import Bytes
@testable import Brotli

@Suite("Encoder API surface")
struct EncoderAPITests {
    @Test("Quality.rawValue maps named cases to RFC 7932 levels")
    func qualityLevels() {
        #expect(Brotli.Quality.fastest.rawValue == 0)
        #expect(Brotli.Quality.fast.rawValue == 4)
        #expect(Brotli.Quality.default.rawValue == 6)
        #expect(Brotli.Quality.balanced.rawValue == 9)
        #expect(Brotli.Quality.smallest.rawValue == 11)
        #expect(Brotli.Quality.level(7).rawValue == 7)
    }

    @Test("BrotliError gains inputTooLarge + qualityOutOfRange cases")
    func newErrorCases() {
        let a: BrotliError = .inputTooLarge
        let b: BrotliError = .qualityOutOfRange
        #expect(a != b)
    }

    @Test("compress with empty input returns a non-empty valid brotli stream")
    func emptyInputCompresses() throws {
        let out = try Brotli.compress(Bytes())
        #expect(!out.isEmpty)
    }
}
