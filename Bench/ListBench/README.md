# ListBench 基准测试说明

> 配套文章：[NSTableView重写实录](../NSTableView重写实录/NSTableView重写实录.html)
> 目的：在不依赖 SwiftUI/AppKit 的纯 Swift 维度上，量化三种列表渲染方案在"行数据构造 + UUID 累加"这一步骤的耗时。

## 跑法

本仓库的 `Package.swift` 默认**不包含** ListBench target（避免污染主产品），但 `Bench/ListBench/main.swift` 是完整可用的。要在本地复跑：

```bash
# 1. 临时把 ListBench 加进 Package.swift 的 targets 列表
# 2. 然后：
swift run ListBench
```

跑完结果会包括三组方案各 3 次测量的平均 + max，单位 ms。

## 真实结果（本机：iMac 2019 / Debug 构建）

| 方案 | 3 次平均 | max |
|---|---|---|
| [A] OutlineGroup 全树实例化（10,401 行） | 2.92 ms | 2.99 ms |
| [B] 懒加载 400 行/批 | 2.94 ms | 3.02 ms |
| [C] NSTableView 60 行窗口 | 2.86 ms | 3.02 ms |

## 结论

**三方案在纯 Swift 构造维度上几乎打平**（约 3 ms）。这恰恰说明：在 SwiftUI/NSTableView 性能话题里，**纯数据构造不是瓶颈**。真正的瓶颈是 SwiftUI 框架层的 body 投影、KeyPath 求值、DynamicProperty 解析、约束布局等——这些只有用 Instruments Time Profiler 才能看见（详见文章第三节）。

如果谁跟你说"NSTableView 比 SwiftUI List 快 10 倍"而没有具体场景，**让他跑一遍这个 benchmark 给他看**。
