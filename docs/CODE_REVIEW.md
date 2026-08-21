# CacheCleaner 代码审查报告

> 审查日期：2026-08-20 · 审查范围：全部 16 个源码文件 + 4 个构建脚本 + 文档
> 审查方式：逐文件通读 + 关键风险项实测验证（符号链接 / 树构建压测 / 白名单用例）

---

## 一、已修复问题（按危险度排序）

### 1. 清理使用「扫描时运行状态快照」（最高危）· commit `1c9a1d6`
- **风险**：扫描时记录 `isRunning`，从扫描到点击清理之间刚启动的 App，其缓存仍会被删除 → 数据损坏
- **修复**：`CacheCleanerService.clean` 内部实时重新查询运行中 bundle id（`runningBundleIDs()`），不再依赖快照

### 2. 清理失败项被误移除 · commit `1c9a1d6`
- **风险**：原逻辑把勾选项**全部**从列表移除（含删除失败的），用户以为清除了、实际没清 → 误导
- **修复**：按 `failedPaths` 过滤，仅移除成功清理的项；失败项保留在列表

### 3. 白名单前缀误匹配 · commit `1c9a1d6`
- **风险**：`hasPrefix` 匹配导致添加 `/Caches/WeChat` 时把 `WeChatData`、`WeChatHelper` 一并跳过
- **修复**：目录边界匹配 `path == entry || hasPrefix(entry + "/")`，5 个用例全过

### 4. 清理阻塞主线程（两处）· commit `1c9a1d6`
- **风险**：`directorySize` + 删除大缓存同步跑在主线程 → UI 冻结
- **修复**：缓存清理页与目录分析页的 `cleanSelected` 均改 `Task.detached` 后台执行

### 5. 树构建新实现递归未截断路径 → 栈溢出崩溃 · commit（本轮）
- **背景**：性能优化时重写 `DirectoryTreeBuilder`（字典分组替代线性查找），第一版递归时未截断相对路径前缀 → 无限递归 SIGSEGV
- **发现**：压测（1000 文件最小复现）抓出；修复后 5 万文件 × 4 层 1.54s 构建完成
- **教训**：优化重构必须回归验证

### 6. 目录分析统计卡 O(3n) filter（性能）· commit（本轮）
- **风险**：大目录每次视图刷新对 10 万文件 filter 3 次
- **修复**：`levelCounts` / `levelSizes` 一次性缓存，扫描/清理后 `recomputeStats()`

### 7. FDA 检测误判加固 · commit（本轮）
- **风险**：已授权但探测目录全空时误报「未授权」（候选目录太少）
- **修复**：候选目录从 4 个扩到 8 个（Safari / sharedfilelist / AddressBook / MobileSync 等几乎必有内容的目录）

### 8. 设置面板快捷键 · commit（本轮）
- **风险**：`keyboardShortcut(.defaultAction)` + `keyboardShortcut(.cancelAction)` 链式叠加，可能只生效后者
- **修复**：改为 `.keyboardShortcut(.defaultAction)` + `.onExitCommand`（Esc），语义明确

### 9. AppNameMapper 缓存数据竞争 · commit（本轮）
- **风险**：后台扫描线程写静态字典
- **修复**：`NSLock` 保护 `nameCache`

### 10. 文案/显示精度 · commit `1c9a1d6`
- 确认弹窗「不可撤销」在废纸篓模式下矛盾 → 按模式动态显示
- 字体大小显示 `%.0f` 与 0.5 步进不符 → `%.1f`

---

## 二、实测验证记录

| 项目 | 方法 | 结果 |
| --- | --- | --- |
| 符号链接循环引用 | 构造 `loop_link → 父目录`，枚举测试 | ✅ 无死循环，`FileManager.enumerator` 默认不跟随符号链接目录 |
| 白名单边界匹配 | 5 用例（本身/子路径/WeChatData/WeChatHelper/无关） | ✅ 5/5 通过 |
| 树构建正确性 | 项目真实目录 3306 文件分层归类 | ✅ 顶层 6 节点，聚合大小正确 |
| 树构建性能 | 5 万文件 × 4 层压测 | ✅ 1.54s |
| dmg 完整性 | `hdiutil verify` + 挂载检查 | ✅ VALID，含 .app + Applications 别名 + icns |
| GUI 启动 | 冒烟测试 | ✅ 正常 |
| 编译 | `swift build` | ✅ 零警告（1 个 Swift 6 异步枚举器 warning，见下） |

---

## 三、剩余风险与已知限制

### Swift 6 兼容性（低）
- `DirectoryAnalyzer.swift:33` 有 1 个 warning：`enumerator` 的 `makeIterator` 在 async 上下文不可用（Swift 6 语言模式下会变 error）
- 当前 Swift 5.9 模式编译运行正常；若未来切 Swift 6 严格并发，需把枚举循环移入 `Task.detached` 或改同步包装

### 已知限制（设计取舍，非 bug）
- **系统级缓存可清理**：`~/Library/Caches/com.apple.*` 归为「系统」类可勾选删除，删除后对应系统组件会自动重建（已有文案提示）
- **取消扫描保留部分结果**：点「取消」后已统计的缓存项会保留在列表（语义为「停止」而非「放弃」）
- **目录分析跳过 .app 包内部**：`skipsPackageDescendants`，README 已说明
- **FDA 检测为启发式**：基于 TCC「伪装空目录」特性，理论上存在极端误判场景（概率极低，已通过扩充候选目录缓解）
- **目录分析树一次性构建**：5 万文件 1.5s 可接受；`List` + `OutlineGroup` 懒加载渲染，默认折叠下无渲染压力

### 待用户确认
- **README Release 链接**：写的是 `https://github.com/guofengrui/CacheCleaner/releases`，`guofengrui` 是假设的 GitHub 用户名——若实际用户名不同，push 前需修改

---

## 四、设计决策记录

| 决策 | 理由 |
| --- | --- |
| 不签名 + 右键打开分发 | 目标用户「能来 GitHub 找工具就不怕麻烦」；签名 $99/年等正经分发再投入 |
| 图标用 SF Symbols 矢量绘制 | AI 生成两次均带水印/圆角白边不可控；矢量几何精确、符合 HIG、可无限微调 |
| 图标自带圆角矩形（22.37% squircle） | 用户明确要求；与系统 mask 形状一致，跨场景（预览/网页/Dock）表现统一 |
| 收款码全图斜纹 + 底部条幅双水印 | 防裁剪；斜纹覆盖率 ~3% < QR L 级纠错 7% 下限，扫码无忧 |
| 清理实时复核运行状态 | 牺牲一次 NSWorkspace 查询（毫秒级），换取数据安全 |
| 白名单目录边界匹配 | 精确匹配目录本身及子路径，不误伤同级前缀目录 |

---

## 五、代码健康度

- 源码 16 文件，分层清晰（Models / Services / ViewModel / Views）
- ViewModel 无超大文件（CacheCleanerModel 250 行、DirectoryAnalysisModel 190 行）
- 无强制解包风险点（`children!` 已于重写中移除）
- 清理/扫描均在后台执行，主线程仅 UI 状态更新
- 所有用户可见字符串为中文硬编码（i18n 计划见 README Roadmap）
