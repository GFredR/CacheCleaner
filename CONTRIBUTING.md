# 参与贡献 Contributing

**中文**

先说清楚现状，免得你有预期落差：**这个项目目前 0 issue、0 PR、1 star。** 收到的最多的是 bug 报告，代码贡献极少。所以下面「怎么让报告可被处理」写得比「怎么提 PR」详细得多。

## ⚠️ 如果文件被误删了，先看这里

**v1.1.1 起，清理默认移入废纸篓**（不是直接删除）。如果你开了这个开关：

1. **立刻打开废纸篓**，那里什么都有 —— 恢复是拖回去就行。
2. 没开的话，说明你的设置里「清理时移入废纸篓」是关的（手动设过的会保留你的选择），那就没有兜底可捡了。

**如果你想我帮你找回**：先别做别的事，告诉我删的是什么（路径、大概体积），我需要知道清理走的是哪条代码路径。

## 提 issue 前，先自查三条

1. **是不是权限问题？** 没授予「完全磁盘访问」时，TCC 保护的目录不可见，**扫描结果会比 CleanMyMac 少很多**。设置里点「重新检测」会跳到系统设置。
2. **是不是「不该被统计」的东西？** `/Library/Caches` 需要 root，本工具**有意不处理**；`.app` / `.bundle` 包内部默认跳过，只统计外壳 —— 这些是设计决策，不是 bug。
3. **是不是版本问题？** 确认用的是最新版 Release。

这三条能挡掉相当一部分报告。

## 提一份有用的 issue

| 项 | 为什么需要 |
|---|---|
| CacheCleaner 版本 + macOS 版本 | 很多问题跟系统版本强相关 |
| **完整磁盘访问是否已授予** | 决定扫不扫得到那些目录（见上文第一条） |
| 相关目录路径 | 缓存清理 / 目录分析 / 空间洞察三条路径的行为不同 |
| 大概容量与条目数 | 决定是否落在性能边界上 |
| 你做了什么 / 你以为会发生什么 / 实际发生了什么 | 三段式，比「没用」有用一百倍 |
| 截图 | 界面问题必附 |

**涉及误删时，务必说清是哪一步**：是勾选阶段就选错了，还是清理弹窗没拦住？

## 想提 PR

**先开 issue 讨论。** 这个项目没有多人协作，PR 直接扔过来大概率不合上下文。

如果你确定要提：

1. 从一个干净分支开始，一次改动只做一件事；
2. 提交信息写「改了什么」和「为什么」，别写「fix bug」；
3. **本地跑通测试再推**（75 个用例）：

```bash
swift test
```

4. 涉及界面的改动请附截图（改动前后各一）。

### 什么改动我大概率会拒绝

这一条对本项目尤其重要：

- ❌ **任何让删除变得更不可恢复的改动。** 默认进废纸篓是 v1.1.1 才有的，之前默认直接删。如果有人提「加个更快的永久删除开关」，大概率会被拒。
- ❌ **引入第三方依赖。** 刻意为之：纯系统 API、Universal 2 单二进制、零供应链。
- ❌ **后台常驻 / 定时自动清理。** 这是订阅型工具的逻辑，而且会让用户失去「我决定什么时候清」的控制权。
- ❌ **跳过二次确认，或把确认弹窗做得更容易被误点。** 一次误删换来的速度不划算。
- ❌ **顺手重构。** 与改动无关的格式化会把 diff 淹掉。

如果你认为某个决定该推翻，**先开 issue 说服我**，比直接改高效。

## 代码风格

跟仓库现有代码保持一致：

- 注释解释**为什么**，不解释是什么；
- 用户可见文案走 `Localizable.strings`（中英双语），不硬编码；
- **数值格式化必须用 `Locale.ROOT`**，不能用系统默认 —— 德语会出 `1,0 KB`，土耳其语 `"i".uppercase()` 得 `İ`，这类 bug 在开发机上复现不出来；
- 不做「顺手重构」，重构单独一个 commit；
- ⚠️ 单元测试**要测真实的产品代码**。仓库里有几条测试是用 `UserDefaults` 在测试里重演一遍产品逻辑的，那只能证明测试自己没写错；新测试别这么写。

---

**English**

State of the project, up front: **0 issues, 0 PRs, 1 star** so far. Most reports are bugs, so "how to make your report actionable" gets far more space than "how to submit a PR".

## ⚠️ If this app deleted your files

Since **v1.1.1, cleanup moves files to the Trash by default** (before that it deleted them directly). If you had that setting on:

1. **Open the Trash now** — everything is there, and restoring is a drag.
2. If you had it off, your own preference was kept and there's nothing to recover.

**If you need help recovering**: tell me what was deleted (path, rough size) and which cleanup path was used, and don't do anything else until then.

## Before you file

1. **Permissions?** Without Full Disk Access, TCC-protected folders are invisible, so **you'll see far less than CleanMyMac does**.
2. **Something meant to be skipped?** `/Library/Caches` needs root and is deliberately not touched; `.app`/`.bundle` contents are skipped by default (only the shell is counted). These are design decisions, not bugs.
3. **Latest release?** The version matters.

## What makes a report actionable

Include: version + macOS version · **whether Full Disk Access is granted** · the relevant paths (the three features behave differently) · approximate size and item count · what you did, what you expected, what happened · screenshots for UI issues.

If something was deleted, **state at which step**: wrong selection, or the confirm dialog failing to stop it?

## Pull requests

**Open an issue first.** With no collaborators, a PR that arrives without context usually won't land.

If you proceed: one branch, one concern per change · explain *what* and *why* · **run the tests before pushing**:

```bash
swift test      # 75 cases
```

Include before/after screenshots for UI changes.

### Changes I'll likely decline

This matters more here than in most projects:

- ❌ **Anything that makes deletion less recoverable.** Moving to the Trash by default only arrived in v1.1.1; before that it deleted directly. A request for a "faster permanent delete" toggle will likely be declined.
- ❌ **Third-party dependencies.** Deliberate: system APIs only, one Universal 2 binary, zero supply chain.
- ❌ **Background / scheduled automatic cleaning.** That's subscription-tool behaviour, and it takes away the user's control over *when*.
- ❌ **Skipping the confirmation dialog, or making it easier to misclick.** One accidental deletion isn't worth any speedup.
- ❌ **Drive-by refactors.**

## Code style

- Comments explain *why*, not *what*;
- User-facing strings go through `Localizable.strings` (both languages), never hardcoded;
- **Always format sizes with `Locale.ROOT`.** The system locale yields `1,0 KB` in German and `"i".uppercase()` → `İ` in Turkish — neither reproduces on a dev machine;
- No drive-by refactors;
- ⚠️ Unit tests should exercise **real product code**. A few existing tests re-enact the logic with `UserDefaults` instead, which only proves the test itself isn't wrong. Don't write new ones that way.