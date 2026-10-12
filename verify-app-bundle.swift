// 验证打包后的 .app 里，lproj 资源真的能被 Bundle 查到并正确返回翻译
// （而不是只是文件躺在那儿 —— 这个坑真实发生过：build-app.sh 按错路径找资源，
//   `if [ -d ]` 判假后静默跳过，发布产物里一个 .lproj 都没有）
// 用法: swift verify-app-bundle.swift <path/to/App.app> ["中文key"]
import Foundation

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("用法: swift verify-app-bundle.swift <App.app路径> [中文key]\n".data(using: .utf8)!)
    exit(2)
}
let path = CommandLine.arguments[1]
let probeKey = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "缓存清理"

guard let bundle = Bundle(path: path) else {
    FileHandle.standardError.write("✗ 打不开 bundle: \(path)\n".data(using: .utf8)!)
    exit(2)
}
print("bundle        : \(bundle.bundlePath)")
print("localizations : \(bundle.localizations.sorted())")

var failed = false

// 1. 至少要有中英两份，且 bundle 必须「声明」en —— 否则切英文系统语言会静默回落
for loc in ["zh-Hans", "en"] where !bundle.localizations.contains(loc) {
    print("✗ bundle 未声明 \(loc) 本地化")
    failed = true
}
if !bundle.localizations.contains("en") { failed = true }

// 2. 两份表必须存在且内容不同（相同 = 复制错文件，或者根本是同一个表）
if let enPath = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: "en.lproj"),
   let zhPath = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: "zh-Hans.lproj"),
   let en = try? String(contentsOf: URL(fileURLWithPath: enPath), encoding: .utf8),
   let zh = try? String(contentsOf: URL(fileURLWithPath: zhPath), encoding: .utf8) {
    print("en  strings  : \(en.count) 字节 / \(en.split(separator: "\n").count) 行")
    print("zh-Hans      : \(zh.count) 字节 / \(zh.split(separator: "\n").count) 行")
    if en == zh { print("⚠️ 两份表内容相同（可疑）"); failed = true }
} else {
    print("✗ 找不到 zh-Hans/en 的 Localizable.strings")
    failed = true
}

// 3. 用真实 key 强制分别读两张表，确认查得到且译文不同
if let enPath = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: "en.lproj"),
   let zhPath = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: "zh-Hans.lproj") {
    let en = try! String(contentsOf: URL(fileURLWithPath: enPath), encoding: .utf8)
    let zh = try! String(contentsOf: URL(fileURLWithPath: zhPath), encoding: .utf8)
    func lookup(_ table: String, _ key: String) -> String? {
        // 形如: "缓存清理" = "Cache Cleanup";
        let needle = "\"\(key)\" = \""
        guard let r = table.range(of: needle) else { return nil }
        let rest = table[r.upperBound...]
        guard let end = rest.range(of: "\"") else { return nil }
        return String(rest[..<end.lowerBound])
    }
    let zhVal = lookup(zh, probeKey)
    let enVal = lookup(en, probeKey)
    print("key \"\(probeKey)\" → zh: \(zhVal ?? "<<未找到>>")  |  en: \(enVal ?? "<<未找到>>")")
    if zhVal == nil || enVal == nil { print("✗ 探针 key 在表里查不到（探针本身写错了，换个真实 key 再验）"); failed = true }
    else if zhVal == enVal { print("⚠️ 两种语言返回同一句，翻译没生效"); failed = true }
}

if failed {
    FileHandle.standardError.write("✗ 验证未通过\n".data(using: .utf8)!)
    exit(1)
}
print("✓ 打包产物的 i18n 资源可用")