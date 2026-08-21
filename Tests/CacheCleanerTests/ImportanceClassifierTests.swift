import XCTest
@testable import CacheCleaner

final class ImportanceClassifierTests: XCTestCase {

    private func classify(_ path: String) -> ImportanceLevel {
        ImportanceClassifier.classify(url: URL(fileURLWithPath: path))
    }

    // 规则 0a 里普通缓存/产物内容仍算可清理
    func testSafePathSegmentCaches() {
        XCTAssertEqual(classify("/Users/x/Library/Caches/com.tencent.x/foo.log"), .safeToClean)
        XCTAssertEqual(classify("/Users/x/Library/Caches/com.tencent.x/widget.o"), .safeToClean)
        XCTAssertEqual(classify("/Users/x/Projects/A/node_modules/react/dist/bundle.o"), .safeToClean)
        XCTAssertEqual(classify("/Users/x/Library/Developer/Xcode/DerivedData/A/Build/Products/x"), .safeToClean)
    }

    // 危险场景防护：任意业务目录里名为 tmp/cache 子文件夹下的"重要类型"文件，
    // 即便路径命中可清理目录段，也不得标绿（否则会被默认勾选删除）。
    func testSafePathSegmentDoesNotDowngradeImportantExtension() {
        XCTAssertEqual(classify("/Users/x/Projects/A/tmp/合同.docx"), .cautious)
        XCTAssertEqual(classify("/Users/x/个人资料/cache/相册备份.pdf"), .cautious)
        XCTAssertEqual(classify("/Users/x/Projects/B/Logs/notes.md"), .cautious)
        XCTAssertEqual(classify("/Users/x/Projects/C/dist/config.json"), .cautious)
        XCTAssertEqual(classify("/Users/x/Projects/D/node_modules/data.sqlite"), .cautious)
    }

    // 关键文件名的 .env / .gitignore / README 即使位于可清理目录段下也不降级为绿
    func testSafePathSegmentDoesNotDowngradeImportantFileName() {
        XCTAssertEqual(classify("/Users/x/project/cache/.env"), .cautious)
        XCTAssertEqual(classify("/Users/x/project/tmp/.gitignore"), .cautious)
        XCTAssertEqual(classify("/Users/x/project/target/README.md"), .cautious)
    }

    // MARK: - 规则 0b：.git 目录 → 红
    func testGitDirectoryIsImportant() {
        XCTAssertEqual(classify("/Users/x/Project/.git/HEAD"), .important)
        XCTAssertEqual(classify("/Users/x/Project/.git/refs/heads/main"), .important)
    }

    // MARK: - 规则 1：重要文件名 → 红
    func testImportantFileNames() {
        XCTAssertEqual(classify("/x/README"), .important)
        XCTAssertEqual(classify("/x/README.md"), .important)
        XCTAssertEqual(classify("/x/LICENSE"), .important)
        XCTAssertEqual(classify("/x/Makefile"), .important)
        XCTAssertEqual(classify("/x/Package.swift"), .important)
    }

    // MARK: - 规则 2：可清理精确文件名 → 绿
    func testSafeFileNames() {
        XCTAssertEqual(classify("/x/.DS_Store"), .safeToClean)
        XCTAssertEqual(classify("/x/ds_store"), .safeToClean)
        XCTAssertEqual(classify("/x/thumbs.db"), .safeToClean)
    }

    // MARK: - 规则 3：重要扩展名 → 红
    func testImportantExtensions() {
        XCTAssertEqual(classify("/x/doc.pdf"), .important)
        XCTAssertEqual(classify("/x/code.swift"), .important)
        XCTAssertEqual(classify("/x/db.sqlite"), .important)
        XCTAssertEqual(classify("/x/key.pem"), .important)
        XCTAssertEqual(classify("/x/config.json"), .important)
    }

    // MARK: - 规则 4：可清理扩展名 → 绿
    func testSafeExtensions() {
        XCTAssertEqual(classify("/x/app.log"), .safeToClean)
        XCTAssertEqual(classify("/x/build.o"), .safeToClean)
        XCTAssertEqual(classify("/x/cache.tmp"), .safeToClean)
        XCTAssertEqual(classify("/x/cache.pyc"), .safeToClean)
    }

    // MARK: - 规则 6：谨慎扩展名 → 黄
    func testCautiousExtensions() {
        XCTAssertEqual(classify("/x/archive.zip"), .cautious)
        XCTAssertEqual(classify("/x/app.app"), .cautious)
        XCTAssertEqual(classify("/x/backup.bak"), .cautious)
        XCTAssertEqual(classify("/x/lib.dylib"), .cautious)
    }

    // MARK: - 规则 7：兜底 → 黄
    func testUnknownTypeIsCautious() {
        XCTAssertEqual(classify("/x/unknown_no_extension_file"), .cautious)
    }

    // MARK: - 大小写敏感：扩展名应小写比较
    func testExtensionCaseInsensitive() {
        XCTAssertEqual(classify("/x/PHOTO.PDF"), .important)
        XCTAssertEqual(classify("/x/LOG.LOG"), .safeToClean)
    }
}
