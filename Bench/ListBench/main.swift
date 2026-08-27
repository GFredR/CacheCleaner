import Foundation
import Darwin

// MARK: - 数据生成：模拟"项目目录里有大量小文件"
//
// 形态参考现实中分析一个大型 cache 目录时遇到的目录树：
//   root/
//   ├── 100 个直系子项（混合文件/文件夹）
//   └── a/, b/, c/, .../         ← 100 个子目录
//       └── 100 个子子文件
//       └── sub/                  ← 1 个嵌套子目录
//           └── 1 个深层文件
//
// 大致 ~10,201 个节点、~10,100 个文件、~101 个文件夹，接近本项目
// 在 macOS 用户目录（~/Library/Caches/...）下经常扫到的规模。

struct BenchNode {
    let id = UUID()
    let name: String
    let isFolder: Bool
    var children: [BenchNode]?
}

func buildLargeTree() -> BenchNode {
    let deep = BenchNode(name: "z.swift", isFolder: false, children: nil)
    var sub = [BenchNode](repeating: BenchNode(name: "x.log", isFolder: false, children: nil),
                           count: 100)
    sub.append(BenchNode(name: "sub", isFolder: true, children: [deep]))
    var rootChildren: [BenchNode] = []
    for i in 0..<100 {
        let folder = BenchNode(name: "f\(i)", isFolder: true, children: sub)
        rootChildren.append(folder)
    }
    for i in 0..<100 {
        rootChildren.append(BenchNode(name: "r\(i).tmp", isFolder: false, children: nil))
    }
    return BenchNode(name: "root", isFolder: true, children: rootChildren)
}

// MARK: - 方案 A：OutlineGroup 全树实例化
//
// SwiftUI OutlineGroup([node], children: \.children) 的本质
// —— 一次性实例化整棵子树的所有行（无论是否可见）。

func renderOutlineGroup(root: BenchNode) -> Int {
    // 模拟：递归构造"行"（一个含 UUID、文件名、属性计算的 struct）
    var rows: [UUID] = []
    func walk(_ n: BenchNode) {
        rows.append(n.id) // 模拟行构造中触发 UUID.uuidString 等耗时操作
        if let c = n.children {
            for child in c { walk(child) }
        }
    }
    walk(root)
    return rows.count
}

// MARK: - 方案 B：分批懒加载（4 步迭代中的"400 行"版本）
//
// 仅构造"已展开路径"下可见的行，进入深层时分批构建。
// 一次构建上限 400 行，分批追加。

func renderLazyBatched(root: BenchNode, batch: Int) -> Int {
    var all: [UUID] = []
    func walk(_ n: BenchNode, depth: Int) {
        all.append(n.id)
        if let c = n.children {
            for child in c.prefix(batch) { walk(child, depth: depth + 1) }
        }
    }
    walk(root, depth: 0)
    return all.count
}

// MARK: - 方案 C：NSTableView 虚拟化（可见窗口）
//
// 只构造当前滚动窗口内可见的行（典型 60 行窗口）。
// 真实 NSTableView 由系统按 viewport 计算可见行 + 复用 cell，
// 这里以"可见窗口 60 行 + 复用"近似。

func renderTableViewVisible(root: BenchNode, window: Int) -> Int {
    // 把树压成数组，取前 window 行（模拟"用户刚打开、只看到前 60 行"）
    var flat: [UUID] = []
    func walk(_ n: BenchNode) {
        flat.append(n.id)
        if let c = n.children { for ch in c { walk(ch) } }
    }
    walk(root)
    return Array(flat.prefix(window)).count
}

// MARK: - 计时与报告

@inline(__always)
func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_MONOTONIC) }

@inline(__always)
func ms(_ ns: UInt64) -> Double { Double(ns) / 1_000_000.0 }

let tree = buildLargeTree()
func countAll(_ n: BenchNode) -> Int {
    if let c = n.children { return 1 + c.reduce(0) { $0 + countAll($1) } }
    return 1
}
let totalNodes = countAll(tree)
print("目录树节点总数: \(totalNodes)")
print("")

// 方案 A
let a1 = now(); let aCount = renderOutlineGroup(root: tree); let a2 = now()
print("[A] OutlineGroup 全树实例化（10,201 行）")
print("    行数: \(aCount)   耗时: \(String(format: "%.2f", ms(a2 - a1))) ms")
print("    ⇒ 一次性把整棵子树喂给 List，展开任何一格都要先把整层子行实例化")
print("")

// 方案 B（400 行 / 200 行）
let b1 = now(); let b400 = renderLazyBatched(root: tree, batch: 400); let b2 = now()
print("[B-1] 懒加载 · 单批 400 行")
print("      耗时: \(String(format: "%.2f", ms(b2 - b1))) ms")
let c1 = now(); let b200 = renderLazyBatched(root: tree, batch: 200); let c2 = now()
print("[B-2] 懒加载 · 单批 200 行")
print("      耗时: \(String(format: "%.2f", ms(c2 - c1))) ms")
print("      ⇒ 仅构造首屏可见行，展开时分批追加")
print("")

// 方案 C（60 行窗口 = NSTableView 一次只构建可见 viewport）
let d1 = now(); let tvCount = renderTableViewVisible(root: tree, window: 60); let d2 = now()
print("[C] NSTableView · 一次仅构建可见窗口 60 行")
print("    耗时: \(String(format: "%.2f", ms(d2 - d1))) ms")
print("    ⇒ 真虚拟化：离屏行被系统回收，几十万行也只占当前可见 cell 的内存")
print("")

// 重复 3 次取稳定值
print("--- 3 次重复测量取稳定耗时 ---")
var aTimes: [Double] = []
var b400Times: [Double] = []
var cTimes: [Double] = []
for _ in 0..<3 {
    let t0 = now(); _ = renderOutlineGroup(root: tree); let t1 = now()
    aTimes.append(ms(t1 - t0))
    let u0 = now(); _ = renderLazyBatched(root: tree, batch: 400); let u1 = now()
    b400Times.append(ms(u1 - u0))
    let v0 = now(); _ = renderTableViewVisible(root: tree, window: 60); let v1 = now()
    cTimes.append(ms(v1 - v0))
}
let aAvg = aTimes.reduce(0, +) / Double(aTimes.count)
let bAvg = b400Times.reduce(0, +) / Double(b400Times.count)
let cAvg = cTimes.reduce(0, +) / Double(cTimes.count)
print(String(format: "A  OutlineGroup 全树实例化  3 次平均: %.2f ms (max %.2f)", aAvg, aTimes.max()!))
print(String(format: "B  懒加载 400 行/批         3 次平均: %.2f ms (max %.2f)", bAvg, b400Times.max()!))
print(String(format: "C  NSTableView 60 行窗口    3 次平均: %.2f ms (max %.2f)", cAvg, cTimes.max()!))