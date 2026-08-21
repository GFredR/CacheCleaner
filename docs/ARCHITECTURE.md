# CacheCleaner 架构说明

本文档描述 CacheCleaner 的整体架构、模块职责与核心数据流，供后续扩展与维护参考。

## 1. 总体分层

```
┌─────────────────────────────────────────────────────────┐
│  Views（SwiftUI 视图层）                                  │
│  ContentView(Tab) / CacheCleanerView / DirectoryAnalysis │
│  View / CacheRowView / SettingsView                      │
├─────────────────────────────────────────────────────────┤
│  ViewModel（状态与业务编排）                               │
│  CacheCleanerModel       目录分析                        │
│  DirectoryAnalysisModel                                  │
├─────────────────────────────────────────────────────────┤
│  Services（服务层：文件系统 / 权限 / 命名映射）             │
│  CacheScanner  CacheCleanerService  DirectoryAnalyzer    │
│  PermissionService  AppNameMapper                        │
├─────────────────────────────────────────────────────────┤
│  Models（领域模型 + 规则）                                 │
│  CacheItem  ImportanceLevel(分类器)                       │
└─────────────────────────────────────────────────────────┘
```

依赖方向自上而下，视图层只依赖 ViewModel，ViewModel 只依赖 Services / Models，无反向依赖。

## 2. 模块职责

### Models

| 文件 | 职责 |
| --- | --- |
| `CacheItem.swift` | 缓存清理页的单条缓存：URL、名称、分类、大小、运行中/白名单标记 |
| `ImportanceLevel.swift` | 三级重要性（绿/黄/红）+ `ImportanceClassifier` 集中式分类规则 |

### Services

| 文件 | 职责 | 关键点 |
| --- | --- | --- |
| `CacheScanner.swift` | 发现三类缓存根目录；递归统计大小 | `enumerator` 遍历，跳过符号链接；`Task.detached` 后台并行 |
| `CacheCleanerService.swift` | 执行缓存清理 | 只删目录**内容**保留目录；支持废纸篓；跳过运行中/白名单；前缀匹配 |
| `DirectoryAnalyzer.swift` | 递归扫描任意目录，逐文件分类 | `enumerator` + resourceValues；进度回调；取消支持 |
| `PermissionService.swift` | 检测完全磁盘访问权限 | TCC 目录伪装为空的特性：能枚举出受保护目录内容即已授权 |
| `AppNameMapper.swift` | bundle id → App 显示名 | 枚举 `/Applications` 等读 Info.plist，结果缓存 |

### ViewModel

| 文件 | 职责 |
| --- | --- |
| `CacheCleanerModel.swift` | 扫描状态机、勾选集合、清理报告、白名单 CRUD（UserDefaults） |
| `DirectoryAnalysisModel.swift` | 目录扫描状态、按等级统计、绿色项默认勾选、文件级清理 |

设置项（`skipRunningApps` / `useTrash` / 白名单）持久化在 `UserDefaults`：
- `skipRunningApps`、`useTrash` 布尔
- `whitelist` 字符串数组（路径前缀）

## 3. 核心流程

### 3.1 缓存清理流程

```
用户点击「重新扫描」
  └─ CacheCleanerModel.startScan()
       ├─ 快照 whitelist / 运行中 bundle id 集合（避免扫描过程中变化）
       ├─ CacheScanner.discoverCandidates()
       │    ├─ ~/Library/Caches/*                → .application / .system
       │    ├─ ~/Library/Containers/*/Data/Library/Caches → .sandbox
       │    └─ ~/Library/Developer/Xcode/DerivedData/*     → .developer
       ├─ 按 8 个一批 withTaskGroup 并行统计大小（可取消）
       ├─ 过滤空缓存，bundle id → 显示名，标记运行中/白名单
       └─ 按大小降序发布到 UI

用户勾选 → 点击「清理所选」
  └─ CacheCleanerService.clean(items:toTrash:skipRunning:whitelist:)
       ├─ 跳过运行中 / 白名单项
       ├─ 删除目录内容（或移入废纸篓）
       └─ 返回释放字节数与失败清单 → 生成清理报告
```

### 3.2 目录分析流程

```
用户拖入目录 / NSOpenPanel 选择
  └─ DirectoryAnalysisModel.analyze(url)
       └─ DirectoryAnalyzer.analyze(url:onProgress:)
            ├─ enumerator 递归（skipsPackageDescendants，跳过符号链接）
            ├─ 逐文件：resourceValues 取大小 + ImportanceClassifier.classify(url:)
            └─ 进度回调（每 50 个文件）

扫描完成
  ├─ 按等级倒序（红→黄→绿）、同级按大小降序
  ├─ 默认勾选全部绿色（可清理）项
  └─ 统计卡：红/黄/绿数量与大小

用户点击「清理可清理项」
  └─ DirectoryAnalysisModel.cleanSelected(useTrash:)
       ├─ 只处理勾选中的 .safeToClean 文件（红/黄不可勾选）
       ├─ removeItem 或 trashItem
       └─ 移除已删条目，生成释放报告
```

### 3.3 权限检测流程

```
PermissionService.hasFullDiskAccess()
  ├─ 依次检查 ~/Library/Messages、~/Library/Mail、
  │   ~/Library/Containers/com.apple.Safari、~/Library/Application Support/com.apple.TCC
  ├─ 任一受保护目录「存在且能枚举出内容」→ 已授权
  └─ 全部不存在或为空 → 未授权（UI 显示引导横幅）
```

原理：TCC 对未授权进程把受保护目录**伪装成空目录**（`fileExists` 为 true、枚举为空），
因此能枚举出真实内容即可判定已授权。该检测存在极少数误判可能（如目录确实为空），
UI 提供「重新检测」手动兜底。

## 4. 关键设计决策

| 决策 | 理由 |
| --- | --- |
| SPM 组织而非 xcodeproj | `open Package.swift` 即可在 Xcode 运行调试，免维护工程文件 |
| 非沙盒 + 手动授权 | 沙盒 App 无法访问其他 App 的缓存目录，必须非沙盒 + FDA |
| 删内容不删目录 | 缓存目录本身多为 App 预建，保留目录避免运行中 App 因句柄/重建异常 |
| 只删「内容」+ 白名单 + 跳过运行中 | 三重防线，把误删风险压到最低 |
| 分类规则集中单文件 | 规则是产品核心参数，集中便于调整与测试 |
| 扫描批次并行（8 个） | 兼顾吞吐与文件系统 I/O 压力 |
| SPM 可执行文件非 bundle | 入口处 `NSApp.setActivationPolicy(.regular)` 显式激活，否则无 Dock 图标 |

## 5. 已知限制

- `/Library/Caches` 系统级缓存未覆盖（需要 root 权限 helper 进程）
- 目录分析为平面列表，深目录结构下层级感弱
- 缓存「正在使用」判断基于 bundle id 匹配，部分非标准目录名匹配不到会视为非运行中
- 分类器按扩展名/路径规则，无法理解文件真实内容（如伪装扩展名）
