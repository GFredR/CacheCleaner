import XCTest
@testable import CacheCleaner

final class SizeFormatterTests: XCTestCase {

    func testBytesUnder1KB() {
        XCTAssertEqual(SizeFormatter.string(from: 0), "0 B")
        XCTAssertEqual(SizeFormatter.string(from: 512), "512 B")
        XCTAssertEqual(SizeFormatter.string(from: 1023), "1023 B")
    }

    func testKB() {
        XCTAssertEqual(SizeFormatter.string(from: 1024), "1.00 KB")
        XCTAssertEqual(SizeFormatter.string(from: 2048), "2.00 KB")
    }

    func testMBNoTrailingSmallDigits() {
        // 1024*1024 = 1048576 → 1024? wait: value=bytes/1024 then loop.
        // bytes = 1024*1024 → value=1024 → >=1024 → v=1, idx=1(MB) → "1.00 MB"
        XCTAssertEqual(SizeFormatter.string(from: 1024 * 1024), "1.00 MB")
    }

    func testLargeNoDecimalsOver100() {
        // bytes = 100 * 1024 * 1024 → MB value = 100 → >=100 → "%.0f MB"
        XCTAssertEqual(SizeFormatter.string(from: 100 * 1024 * 1024), "100 MB")
    }
}