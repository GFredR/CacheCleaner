# 安全策略 Security Policy

**中文**

## 这个工具会删文件 —— 先说这个

CacheCleaner 的功能是**删除缓存文件**。所以它的安全考量不是「防攻击」，而是**「别让你丢东西」**。

- **v1.1.1 起，清理默认移入废纸篓**（可恢复）。v1.1 及更早默认直接删除。
- 系统缓存（`com.apple.*`）**强制**进废纸篓，即使你关掉了上面的选项。
- 默认**跳过正在运行的 App** 的缓存（Xcode 开着时它的 DerivedData 也会被标记）。
- **白名单**里的路径永不清理。
- 清理前有**二次确认**弹窗，列出要删的项和预计释放量。

删除逻辑开源在 `CacheCleanerService.swift` / `DirectoryAnalysisModel.swift`，你可以自己核对它到底删了什么。

## 数据边界

| 项 | 事实 |
|---|---|
| **网络请求** | **零**。源码里没有任何 `URLSession` / `URLRequest` / `http://`，App 也不申请任何网络相关能力 |
| **数据采集** | 无遥测、无分析、无崩溃自动上传 |
| **持久化的东西** | 只有 `UserDefaults`（白名单、显示设置、清理历史）+ 系统废纸篓 |
| **完全磁盘访问** | **需要**，否则扫不到 TCC 保护的目录（结果会比 CleanMyMac 少很多） |

## ⚠️ 关于权限，两件需要你知道的事

### 1. 这个 App 未签名、不在沙盒里

没有 Apple Developer 签名，也**没有沙盒化**。这意味着：

- 授予「完全磁盘访问」是**高权限授权**，理论上前台能读的范围和你手动用 Finder 打开差不多；
- macOS 不会像 App Store 应用那样限制它的文件访问。

这是个人项目的现状（签名需 $99/年）。如果你觉得风险不可接受，**不用它也完全没问题** —— 它只是个清理缓存的工具。

### 2. 权限检测会碰到你的敏感目录

判断「有没有完全磁盘访问」的标准做法，是试着列举几个受保护目录、看是不是空的。这个 App 检查的路径包括：

```
~/Library/Messages
~/Library/Mail
~/Library/Safari
~/Library/Application Support/com.apple.TCC
~/Library/Application Support/AddressBook
~/Library/Application Support/MobileSync
...
```

**它只调用 `contentsOfDirectory` 读目录名列表来判空，不打开、不读取里面任何文件内容**，也从不显示或存储这些目录里的东西。

我知道这些路径看起来敏感，所以写在这里。如果你不接受这个做法，**这是最该提 issue 的理由**。

## 报告问题

### 如果是「文件被误删了」

**开公开 issue 即可**，并说明：

1. 清理时「移入废纸篓」是开是关（决定能不能找回）；
2. 是哪一步出的问题（勾选阶段选错？还是二次确认没拦住？还是以为白名单生效了？）。

如果误删的内容涉及隐私，**可以先在 issue 里只说「细节私聊」**，我会私信沟通。

### 如果是真正的安全问题

（被人利用的那种，比如特定输入导致执行任意代码）请**不要开公开 issue**，同样开 issue 并注明「希望私下沟通」。

目前这个项目的攻击面很小 —— 本地工具、零网络、零依赖 —— 但如果你找到了，那是我该知道的。

## 已知风险边界（据实列出）

- **未签名** ⇒ 首次打开需在「系统设置 → 隐私与安全性」点「仍要打开」。ad-hoc 签名意味着 macOS 不保证它的完整性。
- **未沙盒化** ⇒ 见上文。
- **权限检测会列举敏感目录**（只读目录名）⇒ 见上文。
- **默认进废纸篓会占空间** ⇒ 清理完记得清废纸篓，否则「释放的空间」还占着。
- **不做全盘扫描** ⇒ 只扫 `~/Library/Caches`、`Containers/*/Data/Library/Caches`、Xcode DerivedData，以及你手动指定分析的目录。

---

**English**

## This app deletes files — say that first

CacheCleaner **deletes cache files**. Its safety story isn't "resist attacks", it's "**don't let you lose data**".

- **Since v1.1.1, cleanup moves to the Trash by default** (recoverable). v1.1 and earlier deleted directly.
- System caches (`com.apple.*`) are **forced** to the Trash even if you turn that off.
- Caches of **running apps are skipped by default** (Xcode's DerivedData is flagged while it's open).
- **Whitelisted** paths are never touched.
- A **confirmation dialog** lists exactly what will go and roughly how much space it frees.

The deletion logic is open source in `CacheCleanerService.swift` / `DirectoryAnalysisModel.swift` — verify for yourself what gets deleted.

## Data boundary

| | |
|---|---|
| **Network requests** | **Zero.** No `URLSession`, no `URLRequest`, no `http://` anywhere in the source; no network capability is requested |
| **Collection** | No telemetry, no analytics, no automatic crash upload |
| **What persists** | `UserDefaults` (whitelist, display settings, cleanup history) + the system Trash |
| **Full Disk Access** | **Required**, or TCC-protected folders stay invisible and you'll see far less than CleanMyMac does |

## ⚠️ Two things about permissions you should know

### 1. This app is unsigned and not sandboxed

There's no Apple Developer signature and **no sandbox**. Which means:

- Granting Full Disk Access is a **broad authorization** — theoretically it can read about as much as you could open in Finder yourself;
- macOS won't constrain its file access the way it constrains App Store apps.

That's the reality of a personal project (signing costs $99/year). If that trade-off isn't acceptable to you, **not using it is a perfectly good decision** — it's only a cache cleaner.

### 2. The permission check touches sensitive folders

The standard way to detect Full Disk Access is to enumerate a few protected folders and see whether they look empty. The paths checked here are:

```
~/Library/Messages
~/Library/Mail
~/Library/Safari
~/Library/Application Support/com.apple.TCC
~/Library/Application Support/AddressBook
~/Library/Application Support/MobileSync
...
```

**It only calls `contentsOfDirectory` to read the list of names and judge emptiness. It never opens or reads any file inside them**, and never displays or stores anything from them.

I know those paths look sensitive, which is why it's written here. If you'd rather this weren't the case, **that's the thing to file an issue about.**

## Reporting

### If this app deleted your files

**Open a public issue** and include:

1. whether "move to Trash" was on or off at the time (determines whether it's recoverable);
2. which step went wrong (wrong selection? the confirm dialog failed to stop it? you expected the whitelist to protect something?).

If the deleted content is private, **open the issue saying "details privately"** and I'll follow up by DM.

### If you found a real security issue

(one that can be exploited — e.g. crafted input leading to arbitrary code execution) please **don't open a public issue**; open one and note that you'd like to talk privately.

The attack surface here is small — a local tool, zero network, zero dependencies — but if you found something, I need to know.

## Known risk boundaries (stated plainly)

- **Unsigned** ⇒ first launch requires "Open Anyway" in System Settings → Privacy & Security. Ad-hoc signing means macOS makes no integrity guarantee for it.
- **Not sandboxed** ⇒ see above.
- **The permission check enumerates sensitive folders** (names only) ⇒ see above.
- **Defaulting to Trash still consumes space** ⇒ empty the Trash afterwards, or the "freed" space isn't really free.
- **No whole-disk scan** ⇒ it only looks at `~/Library/Caches`, `Containers/*/Data/Library/Caches`, Xcode DerivedData, and directories you explicitly hand it.