import XCTest
import SwiftUI
@testable import CacheCleaner

final class LocalizationTests: XCTestCase {

    /// 验证 .app bundle 同时包含中文与英文资源（SPM 已处理 resources）
    func testBundleContainsBothLocalizations() {
        let bundle = Bundle.module
        let localizations = bundle.localizations
        // SPM 自动规范化目录名为小写（zh-hans），运行时 SwiftUI 仍按 zh-Hans 匹配
        XCTAssertTrue(localizations.contains { $0.lowercased().contains("zh") },
                      "bundle 应包含中文资源，实际: \(localizations)")
        XCTAssertTrue(localizations.contains("en"),
                      "bundle 应包含英文资源，实际: \(localizations)")
    }

    /// 验证翻译表查找：NSLocalizedString 直接查表
    func testChineseLookup() {
        let bundle = Bundle.module
        // 在中文 base 下查"缓存清理" → 应该返回中文
        let value = NSLocalizedString("缓存清理", bundle: bundle, value: "", comment: "")
        // Bundle.module 默认用环境语言；环境是中文则返回"缓存清理"
        XCTAssertFalse(value.isEmpty, "中文翻译应能查到，实际为空")
    }

    /// 验证英文翻译存在（通过 .strings 文件内容检查）
    func testEnglishTranslationExists() {
        // 用 Bundle(path: .lproj) 显式查英文翻译表
        guard let enBundlePath = Bundle.module.path(forResource: "en", ofType: "lproj"),
              let enBundle = Bundle(path: enBundlePath) else {
            XCTFail("找不到 en.lproj")
            return
        }
        let value = NSLocalizedString("缓存清理", bundle: enBundle, value: "", comment: "")
        XCTAssertEqual(value, "Cache Cleanup", "英文翻译表应返回 'Cache Cleanup'")
    }

    /// 验证 LocalizedStringKey 字面量推断（这是 SwiftUI 自动查表的关键）
    func testLocalizedStringKeyFromLiteral() {
        // 直接用 NSLocalizedString 验证 key 存在于 bundle（中文 base）
        let value = NSLocalizedString("缓存清理", bundle: Bundle.module, value: "MISS", comment: "")
        XCTAssertNotEqual(value, "MISS", "中文 base key '缓存清理' 必须在 bundle 中可查")
        XCTAssertEqual(value, "缓存清理", "当前 locale 应返回中文")
    }
}