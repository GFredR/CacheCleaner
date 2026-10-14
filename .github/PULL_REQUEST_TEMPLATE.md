# 请先开 issue 讨论 / Please open an issue first

这个仓库目前 **0 PR**，所有改动都是单人审的。直接推 PR 大概率会因上下文不足被关掉。
**先开一个 issue 把「改什么、为什么」讨论一轮**，成本低得多。

This repository has **0 pull requests** so far and every change is reviewed by one person.
Opening an issue to agree on *what* and *why* first is far cheaper than a PR that gets closed.

---

**请在 PR 里补上：**

- [ ] 对应的 issue 编号（**没有的话先开 issue**）
- [ ] 改动的**动机**——不只是「改了什么」
- [ ] `swift test`（75 个用例）通过与否
- [ ] 界面改动的**前后截图**
- [ ] ⚠️ **确认没有让删除变得更不可恢复**（默认进废纸篓是 v1.1.1 才有的，别动它）
- [ ] 确认**没有引入第三方依赖**（纯系统 API、Universal 2 单二进制）
- [ ] 新增的用户可见文案**中英双语都补齐了**（`zh-Hans.lproj` + `en.lproj`）

小改动（错别字、**补充无障碍标注**、补充说明）可以直接推，不用开 issue ——
尤其欢迎补 `accessibilityLabel`，这类改动通常一两行就能改完。