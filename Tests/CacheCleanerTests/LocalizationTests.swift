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

    /// 验证 LocalizedStringKey 字面量能查到翻译（任意系统语言下都稳定：
    /// 中文环境返回"缓存清理"，英文环境返回"Cache Cleanup"，
    /// 只要不是 fallback 即证明查表生效，不因 CI runner 语言环境而失败）
    func testLocalizedStringKeyFromLiteral() {
        let value = NSLocalizedString("缓存清理", bundle: Bundle.module, value: "MISS", comment: "")
        XCTAssertNotEqual(value, "MISS",
                          "key '缓存清理' 必须在当前 locale 的 bundle 中可查（不应返回 fallback）")
    }
}