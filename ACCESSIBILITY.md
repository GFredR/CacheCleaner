# 无障碍支持 Accessibility

**中文**

## 先说验证状态（这段最重要，请先读）

下面写的「已支持」指**代码里确实这么写的**，不是「已通过 VoiceOver 走查」。

- ✅ 列出的功能**已实现**，可在代码中核对
- ⚠️ **标注覆盖不完整** —— 这个项目是逐个控件加的，不是系统性梳理过的
- ⚠️ **尚未做任何 VoiceOver 人工走查**

如果你用 VoiceOver 遇到问题，欢迎开 issue —— 这会是第一条有用的反馈。

## 已标注的部分

代码里有 **7 处 `accessibilityLabel` + 2 处 `accessibilityHint`**（实测），覆盖这些控件：

| 控件 | 标注内容 |
|---|---|
| 设置按钮（缓存清理页 / 目录分析页各一） | 「设置」+ 提示「打开字体大小、白名单、主题等设置」 |
| 按应用聚合的组勾选框 | 「勾选整组〈应用名〉」 |
| 单个缓存项勾选框 | 「勾选 / 取消勾选〈条目名〉」（随状态变） |
| 分类色条 | 分类名（如「缓存」「日志」） |
| 空间洞察的文件行选择 | 「选择 / 取消选择〈文件名〉」 |
| 在 Finder 中显示按钮 | 「在 Finder 中显示〈文件名〉」 |

## 界面设计上照顾到的点

- **不靠颜色单独传达信息。** 重要 / 谨慎 / 可清理三色都配文字标签。
- **进度信息有文字。** 清理进度显示「第几项 / 共几项 + 当前名称」，不是只有一条进度条。
- **不自动播放动效。** 扫描进度是真进度，没有装饰性动画。
- **错误说明在原地。** 失败会区分「权限不足 / 文件被占用 / 其他」，不只弹一个通用失败。

## 已知不足（实测得出的，不是推测）

- ⚠️ **列表本身没有逐行语义。** 屏幕阅读器能读到勾选框和分类色条，但一行缓存的完整信息（路径、体积、所属应用）不会被组织成一句可读的描述。
- ⚠️ **目录分析用的是虚拟化表格**（`NSTableView`，因为万级行要流畅）。虚拟化的代价是屏幕外的行不在可访问性结构里，VoiceOver 逐行浏览时可能跳。
- ⚠️ **清理历史页与空间洞察的表格**没有专门标注。
- ⚠️ **没有单独的「高对比度」选项**，主题只跟随系统（浅色 / 深色 / 跟随）。
- ⚠️ **未做 VoiceOver 走查**，以上都可能还有我没发现的问题。

## 反馈

遇到任何无障碍问题，开一个 issue，标题里带上「Accessibility」。

**这对我有特殊意义** —— 视觉、听觉、操作方面的障碍是我最容易漏掉的部分，而只有真正需要的人才能指出哪里不行。补一句标注通常只要一两行，如果你愿意直接改，那更好。

---

**English**

## Verification status (read this first)

"Supported" below means **the code does it** — not "verified with VoiceOver".

- ✅ Listed items are implemented and checkable in the source
- ⚠️ **The labelling is incomplete** — controls were annotated one by one, not via a systematic pass
- ⚠️ **No VoiceOver walkthrough has been done**

If you hit a problem with VoiceOver, please open an issue — it would be the first useful feedback here.

## What is annotated

There are **7 `accessibilityLabel` and 2 `accessibilityHint` uses** (measured):

| Control | Label |
|---|---|
| Settings button (cleanup tab / analysis tab) | "Settings" + hint about font size, whitelist, theme |
| "Select whole app" checkbox | "Select group 〈app name〉" |
| Per-item checkbox | "Select / Deselect 〈item〉" (changes with state) |
| Category colour bar | category name (e.g. "Caches", "Logs") |
| Space Insight file row selection | "Select / Deselect 〈filename〉" |
| "Show in Finder" button | "Show 〈filename〉 in Finder" |

## Design choices that help

- **Never colour alone.** The important / careful / cleanable grading is always paired with text.
- **Progress is textual.** Cleanup shows "item N of M — current name", not just a bar.
- **Nothing autoplays.** Scan progress is real progress, not decorative animation.
- **Errors are explained in place.** Failures are classified (permission denied / file in use / other) instead of one generic failure.

## Known gaps (measured, not assumed)

- ⚠️ **Rows have no per-row semantics.** A screen reader will reach the checkbox and the category bar, but a row's full information (path, size, owning app) isn't assembled into one readable description.
- ⚠️ **Directory analysis uses a virtualised table** (`NSTableView`, because tens of thousands of rows must stay smooth). Virtualisation means off-screen rows aren't in the accessibility tree, so VoiceOver row-by-row navigation may skip.
- ⚠️ **Cleanup history and the Space Insight tables** carry no dedicated labels.
- ⚠️ **No separate high-contrast option** — the theme only follows the system.
- ⚠️ **No VoiceOver pass**, so there may be problems I haven't found.

## Feedback

Open an issue titled with "Accessibility" if anything here doesn't work for you.

**This matters to me specifically** — visual, hearing and motor limitations are what I miss most when building a tool like this, and only someone who actually needs it can say where it falls short. Adding a label is usually one or two lines; PRs doing that are very welcome.