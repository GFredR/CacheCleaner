# CacheCleaner

> **macOS 磁盘缓存清理与目录分析工具**，用 SwiftUI 写的小桌面 App。扫到你电脑上各 App 缓存让你一键清；拖入任意大目录，自动分析哪些文件重要、哪些能安全删，用颜色直观标识。

<div align="center">

**项目目标**

| 你想做的事 | CacheCleaner 怎么做 |
| --- | --- |
| 腾磁盘空间 | 一键扫描 `~/Library/Caches`、`Containers`、`Xcode DerivedData`，按大小展示，勾选清理 |
| 摸清大目录里有什么 | 拖入任意文件夹，递归扫描 + 红黄绿分级 + 树形展开折叠 + 真实进度条 |
| 不想误删重要文件 | 默认跳过运行中的 App、白名单、可移入废纸篓、清理前二次确认 |

</div>

---

## 📸 界面预览

> 截图待补充：缓存清理列表 / 目录分析（拖入大目录后的红黄绿树形 + 进度条）效果最佳。

---

## ✨ 功能特性

### 缓存清理（默认页）

| 扫描范围 | 说明 |
| --- | --- |
| `~/Library/Caches/*` | 系统和各 App 的缓存，自动区分「应用 / 系统」 |
| `~/Library/Containers/*/Data/Library/Caches` | 沙盒 App（Mac App Store 应用）各自的缓存 |
| `~/Library/Developer/Xcode/DerivedData/*` | Xcode 编译缓存（通常占大头） |

- 并行统计每个缓存目录大小（8 个一批，可取消），按大小降序展示
- 自动把 `com.tencent.xinWeChat` 这类 bundle id 反查为「微信」显示
- 行布局：勾选 + 分类色条 + 应用图标 + 名称/路径 + 实心分类徽标 + 大小
- **安全机制**（详见「安全声明」）：
  - 默认跳过正在运行的 App 的缓存（bundle id 匹配；Xcode 运行时其 DerivedData 也会标记）
  - 白名单路径前缀匹配，强制跳过
  - 只删除缓存目录的**内容**，保留目录本身（App 运行时可正常重建）
  - 可选「移入废纸篓」模式，删除后可恢复
  - 清理前弹窗确认

### 目录分析（第二个 Tab）

拖入任意大目录（或点击选择），App 递归扫描全部文件，按**可清理性**分级并着色：

| 颜色 | 等级 | 含义 | 典型文件 |
| --- | --- | --- | --- |
| 🟢 绿 | 可清理 | 缓存 / 临时 / 日志 / 编译产物，删除安全 | `.tmp` `.log` `.pyc` `.o` `.DS_Store`、`Caches/`、`node_modules/`、`DerivedData/` 内的文件 |
| 🟡 黄 | 谨慎 | 压缩包 / 可执行 / 备份 / 未知类型，可能有用 | `.zip` `.dmg` `.app` `.bak`、无扩展名的文件 |
| 🔴 红 | 重要 | 文档 / 代码 / 数据库 / 媒体 / 密钥 / `.git`，勿删 | `.pdf` `.docx` `.swift` `.py` `.db` `.jpg` `.mp4` `.pem`、`README.md` |

- **真实进度条**：先快速预扫描拿总文件数 → 再正式扫描显示 `已处理 N/M · NN%`
- **树形展示**：文件夹与子文件夹可展开/折叠，文件夹显示子文件数与聚合大小
- **右键菜单**：任意一行（文件夹或文件）右键 →「在访达中查看」「复制路径」，文件额外「打开」
- 文件列表按重要性倒序、同级按大小降序；绿色项默认勾选，可直接一键清理
- 重要（红）与谨慎（黄）文件**不可勾选、不会被删除**

> 重要性判定规则集中在 `ImportanceClassifier`（见 `Sources/CacheCleaner/Models/ImportanceLevel.swift`），想调整颜色规则只需改这一个文件。

### 设置（齿轮按钮）

- **通用**：跳过正在运行的 App、清理时移入废纸篓、**列表字体大小（11–18pt）**、**主题（跟随系统 / 浅色 / 深色）**、权限检测
- **白名单**：路径前缀匹配强制跳过

---

## 🛡️ 安全声明

本工具会**删除文件**，请先了解它的行为边界：

- **清理范围**：只删除缓存目录的**内容**（保留目录本身），App 运行时可正常重建
- **运行保护**：默认跳过正在运行的 App 的缓存（Xcode 开着时其 DerivedData 也会标记）
- **双重确认**：清理前弹窗列出将要删除的项目，需手动确认
- **可恢复**：设置里可开启「移入废纸篓」，删除后可恢复
- **可审计**：整个项目开源，删除逻辑在 `CacheCleanerService.swift` / `DirectoryAnalysisModel.swift`，可自行核对；目录分析的绿色标记只是**建议**，勾选后仍会弹窗二次确认
- **免责**：虽经多种保护，仍建议对重要数据保持备份习惯

---

## 📦 安装

### 方式一：dmg 安装包（推荐普通用户）

从 [Releases](https://github.com/guofengrui/CacheCleaner/releases) 下载 `CacheCleaner-1.0.dmg`，双击打开后将 `CacheCleaner.app` 拖到右侧的「Applications」文件夹即可。

> **首次打开**：本项目当前**未做 Developer ID 签名与公证**（个人开发者账号需 $99/年）。未签名的 `.app` 在 macOS 上会被 Gatekeeper 拦截，打开方式二选一：
> 1. **右键点击** `CacheCleaner.app` → 选择「打开」→ 在弹窗中再次点「打开」
> 2. 或终端执行（一次性去除隔离属性）：
>    ```bash
>    xattr -d com.apple.quarantine /Applications/CacheCleaner.app
>    ```
> 不是病毒提示——任何未签名 App 都是这个待遇。项目完全开源，代码可自行审计后再运行。

### 方式二：自己构建（开发者 / 折腾用户）

需要 macOS 13+ 和 Xcode 命令行工具。

#### 用脚本打 dmg

```bash
git clone https://github.com/guofengrui/CacheCleaner.git
cd CacheCleaner
./make-dmg.sh   # 自动构建 .app 并打成 CacheCleaner-1.0.dmg
open CacheCleaner-1.0.dmg
```

#### 用 Xcode 开发调试

```bash
open Package.swift
```

选 `CacheCleaner` scheme 后 ⌘R 运行。**注意**：Xcode 直接运行时窗口会显示「通用可执行」图标（不带自定义图标）。

#### 用命令行跑（最快）

```bash
swift run CacheCleaner
```

> 在受限 CI / 沙盒环境编译若遇 `sandbox-exec: Operation not permitted`，使用 `swift build --disable-sandbox`。

### 首次使用：授予「完全磁盘访问权限」

macOS 的隐私保护（TCC）会让未授权的 App 看不到其他应用的数据目录，扫描结果会不完整。

1. 启动 App，顶部出现「未授权」提示（红点）
2. 点击「开始扫描」时若有未授权，会弹窗询问是否打开系统设置授权
3. 回到 App 点顶部「重新检测」确认授权状态

> 不授权也能用，只是沙盒容器的缓存扫描不完整；点扫描时会弹窗提示，但不会强制打断。

---

## 🎨 外观设置

点击主窗口右上角 **⚙️ 齿轮** → 通用 Tab：

- **列表字体大小**（11–18pt 滑块）：影响缓存列表与目录分析列表的所有文字
- **主题**（跟随系统 / 浅色 / 深色）：即时切换，主窗口与设置窗口同步生效

App 颜色全部使用 SwiftUI 系统语义色（`.green` `.orange` `.red` `.secondary` 等），暗黑模式下不需要任何特殊处理就能保持对比度与可读性。

---

## 🏗️ 项目结构

```
CacheCleaner/
├── Package.swift                          # SPM 清单（macOS 13+）
├── README.md
├── LICENSE                                # MIT
├── docs/
│   └── ARCHITECTURE.md                    # 架构与数据流说明
├── .github/workflows/build.yml            # GitHub Actions CI（自动 swift build）
├── build-app.sh                           # 把 SPM 产物打成 CacheCleaner.app
├── build-icon.swift                       # 生成默认占位图标（仅当未自定义时）
├── build-dmg-background.swift             # 生成 dmg 安装背景图
├── make-dmg.sh                            # 一键打成 CacheCleaner-<version>.dmg
├── Resources/
│   ├── AppIcon.png                        # 1024x1024 图标（已用 AI 设计，可替换）
│   ├── dmg-background.png                 # dmg 安装器背景图（自动生成）
│   └── donate-wechat.png                  # 微信收款码（打赏用，自行放入）
└── Sources/CacheCleaner/
    ├── CacheCleanerApp.swift              # 入口：WindowGroup + Settings
    ├── Models/
    │   ├── CacheItem.swift                # 缓存项模型
    │   ├── ImportanceLevel.swift          # 重要性分级 + 分类器
    │   ├── DirectoryNode.swift            # 目录树节点 + 构建器
    │   └── AppearanceMode.swift           # 跟随系统/浅色/深色
    ├── Services/
    │   ├── CacheScanner.swift             # 缓存目录发现 + 大小统计
    │   ├── CacheCleanerService.swift      # 缓存清理（删除内容 / 废纸篓）
    │   ├── DirectoryAnalyzer.swift        # 目录递归扫描 + 分类 + 进度回调
    │   ├── PermissionService.swift        # 完全磁盘访问权限检测
    │   └── AppNameMapper.swift            # bundle id → App 显示名
    ├── ViewModel/
    │   ├── CacheCleanerModel.swift        # 缓存清理页状态
    │   └── DirectoryAnalysisModel.swift   # 目录分析页状态（含树 + 进度）
    └── Views/
        ├── ContentView.swift              # 主窗口 Tab 容器
        ├── CacheRowView.swift             # 缓存列表行（色条 + 实心徽标 + 右键）
        ├── DirectoryAnalysisView.swift    # 目录分析页（拖拽/统计/树形/进度）
        ├── SettingsView.swift             # 设置（白名单/通用/外观）
        └── SettingsContainer.swift        # 设置 sheet 容器（带完成按钮）
```

---

## 🔧 扩展指南

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

### 替换 App 图标

```bash
# 准备一张 1024×1024 PNG（建议方形带圆角，与 macOS Big Sur 风格统一）
cp my-icon.png Resources/AppIcon.png
./build-app.sh    # 重新打 .app
./make-dmg.sh     # 重新打 dmg
```

### 新增缓存扫描源

在 `CacheScanner.discoverCandidates()` 中追加一段即可，例如模拟器缓存：

```swift
// 4. iOS 模拟器数据（可选）
let sim = home.appendingPathComponent("Library/Developer/CoreSimulator")
// ... 枚举后 append ScanCandidate(url:category:.developer)
```

### 添加界面国际化（可选）

当前所有 UI 字符串是中文硬编码。若需扩展到英文用户，可：
1. 在 `Package.swift` 给 target 加 `defaultLocalization: "en"`
2. 创建 `Sources/CacheCleaner/Resources/en.lproj/Localizable.strings` 或 `.xcstrings`
3. 把硬编码 `Text("...")` 改为 `Text("...".localized())` 或 `Text(LocalizedStringKey("..."))`

---

## ❓ 常见问题

**清理后 App 异常？**
缓存被删后部分 App 需要重启才能重建缓存；若启用了「跳过运行中 App」，运行中的不会被清理。

**为什么扫描结果比 CleanMyMac 少？**
未授权「完全磁盘访问权限」时，受 TCC 保护的目录不可见；另外本工具暂不处理系统级缓存 `/Library/Caches`（需 root）。

**删除的文件能找回吗？**
默认直接删除不可找回；在「设置 → 通用」里打开「清理时移入废纸篓」后可恢复。

**为什么 `swift run` 启动的 App 图标像终端？**
SPM 的 `swift run` 跑的是裸可执行文件，不是 `.app` bundle，没有 `CFBundleIconName`，macOS 会用「通用可执行」图标兜底。`./build-app.sh` 把它打成 `.app` 并附带 AppIcon 后即可显示自定义图标。

**dmg 打开后窗口没有背景图？**
当前打包脚本会在可挂载环境下用 AppleScript 设置 Finder 窗口布局；若你环境的 `hdiutil attach` 受限，dmg 会按默认布局打开（仍可正常拖拽安装）。背景图是锦上添花。

**如何卸载？**
直接拖 `CacheCleaner.app` 到废纸篓即可。设置项存在 `~/Library/Preferences/com.guofengrui.cachecleaner.plist`，可选清理。

**能上 Mac App Store 吗？**
不能。需要 Apple 开发者账号（$99/年）+ 沙盒适配 + 完整审核。本项目按"个人工具 + GitHub 分发"设计，未做这两件事。

---

## 🛣️ Roadmap

- [ ] Developer ID 签名 + 公证（可分发给非开发者用户）
- [x] ~~App 图标与 `.app` 打包~~（`build-app.sh`）
- [x] ~~dmg 安装包~~（`make-dmg.sh`）
- [x] ~~目录分析树形展示~~（OutlineGroup 展开折叠）
- [x] ~~目录分析真实进度条~~（预扫描 + 正式扫描）
- [x] ~~暗黑模式 / 跟随系统~~（设置面板可切换）
- [ ] `/Library/Caches` 系统级缓存（需 root 权限 helper）
- [ ] CoreSimulator 模拟器缓存扫描
- [ ] 重要文件预览（Quick Look）
- [ ] 界面国际化（英文 UI + README.en.md）

---

## 🤝 贡献

欢迎提 Issue / PR：
- 新增缓存扫描源：在 `CacheScanner` 补充
- 调整重要性规则：改 `ImportanceClassifier`，并附用例说明
- UI 改进：保持 SwiftUI 默认样式，避免引入额外依赖

代码风格遵循 [iOS 完整项目开发全局规范](https://github.com/guofengrui/workspace)：

提交信息使用 Conventional Commits（`feat:` `fix:` `docs:` `chore:` `refactor:` 等）。

---

## ☕ 支持一下

如果这个工具帮到了你，欢迎请作者喝杯咖啡。完全自愿，感谢每一份支持：

![微信收款码](Resources/donate-wechat.png)

> 收款码仅用于本项目的自愿打赏，请勿他用。

---

## 📄 License

[MIT](LICENSE) © 2026 郭丰锐 (Guo Fengrui)