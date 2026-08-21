# CacheCleaner

macOS 磁盘缓存清理与目录分析工具（SwiftUI）。

一键扫描电脑里的缓存目录、按大小展示并清理；也可以拖入任意大目录，自动分析里面哪些文件重要、哪些可以安全清理，用颜色直观标识。

- 平台：macOS 13.0+（Ventura 及以上）
- 技术栈：Swift 5.9 + SwiftUI + Swift Package Manager
- 非沙盒应用（需要访问其他 App 的缓存目录）
- 开源协议：MIT

---

## 界面预览

> 截图待补充：缓存清理列表 / 目录分析（拖入大目录后的红黄绿树形列表 + 进度条）效果最佳。

---

## 安全声明

本工具会**删除文件**，请先了解它的行为边界：

- **清理范围**：只删除缓存目录的**内容**（保留目录本身），App 运行时可正常重建
- **运行保护**：默认跳过正在运行的 App 的缓存（Xcode 开着时其 DerivedData 也会标记）
- **双重确认**：清理前弹窗列出将要删除的项目，需手动确认
- **可恢复**：设置里可开启「移入废纸篓」，删除后可恢复
- **可审计**：整个项目开源，删除逻辑在 `CacheCleanerService.swift` / `DirectoryAnalysisModel.swift`，可自行核对；目录分析的绿色标记只是**建议**，勾选后仍会弹窗二次确认
- **免责**：虽经多种保护，仍建议对重要数据保持备份习惯

---

## 功能特性

### 1. 缓存清理

| 扫描范围 | 说明 |
| --- | --- |
| `~/Library/Caches/*` | 系统和各 App 的缓存，自动区分「应用 / 系统」 |
| `~/Library/Containers/*/Data/Library/Caches` | 沙盒 App（Mac App Store 应用）各自的缓存 |
| `~/Library/Developer/Xcode/DerivedData/*` | Xcode 编译缓存，通常占大头 |

- 并行统计每个缓存目录大小（8 个一批，可取消），按大小降序展示
- 自动把 `com.tencent.xinWeChat` 这类 bundle id 反查为「微信」显示
- **安全机制**：
  - 默认跳过正在运行的 App 的缓存（bundle id 匹配；Xcode 运行时其 DerivedData 也会标记）
  - 白名单路径前缀匹配，强制跳过
  - 只删除缓存目录的**内容**，保留目录本身（App 运行时可正常重建）
  - 可选「移入废纸篓」模式，删除后可恢复
  - 清理前弹窗确认

### 2. 目录分析

拖入任意大目录（或点击选择），App 递归扫描全部文件，按**可清理性**分级并着色：

| 颜色 | 等级 | 含义 | 典型文件 |
| --- | --- | --- | --- |
| 🟢 绿 | 可清理 | 缓存 / 临时 / 日志 / 编译产物，删除安全 | `.tmp` `.log` `.pyc` `.o` `.DS_Store`、`Caches/`、`node_modules/`、`DerivedData/` 内的文件 |
| 🟡 黄 | 谨慎 | 压缩包 / 可执行 / 备份 / 未知类型，可能有用 | `.zip` `.dmg` `.app` `.bak`、无扩展名的文件 |
| 🔴 红 | 重要 | 文档 / 代码 / 数据库 / 媒体 / 密钥 / `.git`，勿删 | `.pdf` `.docx` `.swift` `.py` `.db` `.jpg` `.mp4` `.pem`、`README.md` |

- 顶部统计卡片：红 / 黄 / 绿 各自的数量与占用
- **树形展示**：文件夹与子文件夹可展开/折叠，文件夹显示子文件数与聚合大小，文件按重要性保留红黄绿着色
- **右键菜单**：任意一行（文件夹或文件）右键 →「在访达中查看」「复制路径」，文件额外「打开」
- 文件列表按重要性倒序、同级按大小降序；绿色项默认勾选，可直接一键清理
- 重要（红）与谨慎（黄）文件**不可勾选、不会被删除**

> 重要性判定规则集中在 `ImportanceClassifier`（见 `Sources/CacheCleaner/Models/ImportanceLevel.swift`），想调整颜色规则只需改这一个文件。

### 3. 设置页

- **通用**：跳过正在运行的 App、清理时移入废纸篓、列表字体大小（11–18pt，应用于所有列表行）、权限检测
- **白名单**：路径前缀匹配强制跳过

---

## 快速开始

### 方式一：Xcode（开发调试推荐）

```bash
open Package.swift
```

选择 `CacheCleaner` scheme 后 ⌘R 运行。**注意**：用 Xcode 直接运行时 Dock/窗口会显示「通用可执行」图标（不带自定义图标）。

### 方式二：打 `.app` 包（带自定义图标 + 可分发）

```bash
./build-app.sh
open CacheCleaner.app
```

脚本会编译 release 版本，生成 `Resources/AppIcon.png`（默认 Swift 渲染的扫帚+星星图标），并打成 `CacheCleaner.app`（含多尺寸 `.icns` + `Info.plist`）。

**替换为自己的图标**：

```bash
# 准备 1024x1024 PNG（可正方形可带圆角），覆盖默认：
cp my-icon.png Resources/AppIcon.png
./build-app.sh
```

### 方式三：直接命令行跑（最快）

```bash
swift run CacheCleaner
```

> 注：若在受限的 CI / 沙盒环境编译遇到 `sandbox-exec: Operation not permitted`，使用 `swift build --disable-sandbox`。

### 下载预编译版本（Release）

本项目当前**未做 Developer ID 签名与公证**（个人开发者账号需 $99/年）。从网上下载未签名的 `.app`，macOS 的 Gatekeeper 会拦截，首次打开方式：

1. **右键点击** `CacheCleaner.app` → 选择「打开」→ 在弹窗中再次点「打开」
2. 或终端执行（一次性去除隔离属性）：

```bash
xattr -d com.apple.quarantine /path/to/CacheCleaner.app
```

> 这不是病毒提示——任何未签名 App 都是这个待遇。项目完全开源，代码可自行审计后再运行。

### 首次使用：授予「完全磁盘访问权限」

macOS 的隐私保护（TCC）会让未授权的 App 看不到其他应用的数据目录，扫描结果会不完整。

1. 启动 App，顶部出现「未授权」提示（红点）
2. 点击「开始扫描」时若有未授权，会弹窗询问是否打开系统设置授权
3. 回到 App 点顶部「重新检测」确认授权状态

> 不授权也能用，只是沙盒容器的缓存扫描不完整；点扫描时会弹窗提示，但不会强制打断。

---

## 项目结构

```
CacheCleaner/
├── Package.swift                          # SPM 清单（macOS 13+）
├── README.md
├── docs/
│   └── ARCHITECTURE.md                    # 架构与数据流说明
├── build-app.sh                           # 打包脚本（生成 CacheCleaner.app + .icns）
├── build-icon.swift                       # Swift 渲染占位图标
├── Resources/
│   ├── AppIcon.png                        # 1024x1024 图标（首次打包时自动生成，可替换）
│   └── donate-wechat.png                  # 微信收款码（打赏用，自行放入）
└── Sources/CacheCleaner/
    ├── CacheCleanerApp.swift              # 入口：WindowGroup + Settings，非 bundle 激活
    ├── Models/
    │   ├── CacheItem.swift                # 缓存项模型（缓存清理页）
    │   ├── ImportanceLevel.swift          # 重要性分级 + 分类器（目录分析页）
    │   └── DirectoryNode.swift            # 目录树节点 + 构建器
    ├── Services/
    │   ├── CacheScanner.swift             # 缓存目录发现 + 大小统计
    │   ├── CacheCleanerService.swift      # 缓存清理（删除内容 / 废纸篓）
    │   ├── DirectoryAnalyzer.swift        # 目录递归扫描 + 分类
    │   ├── PermissionService.swift        # 完全磁盘访问权限检测
    │   └── AppNameMapper.swift            # bundle id → App 显示名
    ├── ViewModel/
    │   ├── CacheCleanerModel.swift        # 缓存清理页状态
    │   └── DirectoryAnalysisModel.swift   # 目录分析页状态（含树）
    └── Views/
        ├── ContentView.swift              # 主窗口 Tab 容器
        ├── CacheRowView.swift             # 缓存列表行（色条 + 实心徽标）
        ├── DirectoryAnalysisView.swift    # 目录分析页（拖拽/统计/树形）
        └── SettingsView.swift             # 设置（白名单/跳过运行中/废纸篓/字体）
```

---

## 扩展指南

### 调整重要性规则

编辑 `Sources/CacheCleaner/Models/ImportanceLevel.swift` 中的 `ImportanceClassifier`：

```swift
// 想让 .foo 文件显示为绿色（可清理）
safeExtensions.insert("foo")

// 想让某目录下所有内容都标红（重要）
// 在 importantExtensions 或 importantFileNames 中补充
```

规则判定顺序（自上而下优先）：

1. 路径包含可清理目录段（`/Caches/` `/tmp/` `/node_modules/` `/DerivedData/` 等）→ 绿
2. `.git` 目录及其内容 → 红
3. 重要文件名（README / LICENSE / Makefile 等）→ 红
4. 可清理精确文件名（`.DS_Store` 等）→ 绿
5. 扩展名命中重要集合 → 红
6. 扩展名命中可清理集合 → 绿
7. 目录名命中可清理集合 → 绿
8. 扩展名命中谨慎集合 → 黄
9. 兜底（未知类型）→ 黄

### 新增缓存扫描源

在 `CacheScanner.discoverCandidates()` 中追加一段即可，例如模拟器缓存：

```swift
// 4. iOS 模拟器数据（可选）
let sim = home.appendingPathComponent("Library/Developer/CoreSimulator")
// ... 枚举后 append ScanCandidate(url:category:.developer)
```

---

## Roadmap

- [ ] Developer ID 签名 + 公证（可分发给他人）
- [x] ~~App 图标与 `.app` 打包~~（已通过 `build-app.sh` 完成，本地可运行）
- [ ] `/Library/Caches` 系统级缓存（需 root 权限 helper）
- [ ] CoreSimulator 模拟器缓存扫描
- [x] ~~目录分析树形展示（当前为平面列表）~~（已实现 OutlineGroup 展开折叠）
- [ ] 重要文件预览（Quick Look）

---

## 常见问题

**清理后 App 异常？**
缓存被删后部分 App 需要重启才能重建缓存；若启用了「跳过运行中 App」，运行中的不会被清理。

**为什么扫描结果比 CleanMyMac 少？**
未授权「完全磁盘访问权限」时，受 TCC 保护的目录不可见；另外本工具暂不处理系统级缓存 `/Library/Caches`（需 root）。

**删除的文件能找回吗？**
默认直接删除不可找回；在「设置 → 通用」里打开「清理时移入废纸篓」后可恢复。

**为什么 `swift run` 启动的 App 图标像终端？**
SPM 的 `swift run` 跑的是裸可执行文件，不是 `.app` bundle，没有 `CFBundleIconName`，macOS 会用「通用可执行」图标兜底。`./build-app.sh` 把它打成 `.app` 并附带 AppIcon 后即可显示自定义图标（默认 Swift 渲染的扫帚+星星图标，可替换为你的 1024x1024 PNG）。

---

## 支持一下 ☕

如果这个工具帮到了你，欢迎请作者喝杯咖啡。完全自愿，感谢每一份支持：

![微信收款码](Resources/donate-wechat.png)

> 收款码仅用于本项目的自愿打赏，请勿他用。

---

## License

[MIT](LICENSE) © 2026 郭丰锐
