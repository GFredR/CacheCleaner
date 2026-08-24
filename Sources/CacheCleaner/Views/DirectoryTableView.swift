import SwiftUI
import AppKit

// MARK: - Cell 复用宿主

/// 一个可复用的 table cell：内部包一个 NSHostingView 承载 SwiftUI 行内容
private final class RowHostCell: NSTableCellView {
    let hosting = NSHostingView<AnyView>(rootView: AnyView(EmptyView()))

    static let rowID = NSUserInterfaceItemIdentifier("DirectoryAnalysis.Row")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure<V: View>(_ view: V) {
        hosting.rootView = AnyView(view)
    }
}

// MARK: - 控制器

/// 支持按行右键菜单的 NSTableView 子类。
/// 说明：NSTableViewDelegate 虽有 tableView(_:menuFor:row:)，但自绘 cell 场景下
/// 重写 NSView.menu(for:) 按坐标反查行更直接、更可靠（响应链标准机制）。
private final class RowMenuTableView: NSTableView {
    /// 按行号提供右键菜单；返回 nil 不弹菜单
    var rowMenuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return rowMenuProvider?(row(at: point))
    }
}

final class DirectoryTableController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    var model: DirectoryAnalysisModel? {
        didSet {
            guard oldValue !== model else { return }
            reload()
        }
    }
    /// 已应用的结构版本号（避免勾选等不改结构的变化触发 reload）
    var lastRevision: Int = -1
    /// 可见行（扁平）。仅当结构变化时替换，勾选不替换 → 不触发 reload，cell 靠 hostingView 自更新
    var dataRows: [DirectoryRowItem] = [] {
        didSet {
            guard oldValue.map(\.referenceID) != dataRows.map(\.referenceID) else { return }
            reload()
        }
    }
    var isFolderExpanded: (UUID) -> Bool = { _ in false }
    var onToggleExpand: (DirectoryNode) -> Void = { _ in }
    var rowHeight: CGFloat = 36 {
        didSet {
            guard oldValue != rowHeight else { return }
            tableView.rowHeight = rowHeight
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<dataRows.count))
        }
    }
    /// 行内容左右内边距（补偿改 NSTableView 后丢失的 List inset）
    private var rowHorizontalPadding: CGFloat { 12 }

    private lazy var scrollView = NSScrollView()
    private lazy var tableView: RowMenuTableView = {
        let tv = RowMenuTableView()
        tv.headerView = nil
        tv.style = .plain
        tv.allowsColumnReordering = false
        tv.allowsColumnResizing = false
        tv.allowsMultipleSelection = false
        tv.allowsEmptySelection = true
        tv.selectionHighlightStyle = .none
        tv.intercellSpacing = NSSize(width: 0, height: 1)
        tv.rowHeight = rowHeight
        tv.usesAutomaticRowHeights = false
        tv.rowMenuProvider = { [weak self] row in
            self?.menuForRow(row)
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("DirectoryAnalysis.main"))
        tv.addTableColumn(column)
        return tv
    }()

    override func loadView() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        tableView.dataSource = self
        tableView.delegate = self

        let col = tableView.tableColumns[0]
        col.width = 420
        col.minWidth = 200
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle

        view = scrollView
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // 让唯一一列始终填满纵向滚动区宽度
        let width = tableView.enclosingScrollView?.contentSize.width ?? tableView.bounds.width
        if tableView.tableColumns[0].width != width {
            tableView.tableColumns[0].width = width
        }
    }

    private func reload() {
        tableView.reloadData()
    }

    // MARK: - 右键菜单（AppKit 层，自绘 cell 内 SwiftUI contextMenu 不可靠）

    /// 目标节点通过 NSMenuItem.representedObject 随菜单项携带，
    /// 避免"菜单打开期间表格 reloadData 导致共享暂存节点指向错误行"的竞态。
    private func menuForRow(_ row: Int) -> NSMenu? {
        guard dataRows.indices.contains(row) else { return nil }
        let node = dataRows[row].node
        let menu = NSMenu()
        if !node.isFolder, node.file != nil {
            menu.addItem(menuItem("打开", action: #selector(menuOpenFile), node: node))
            menu.addItem(.separator())
        }
        menu.addItem(menuItem("在访达中查看", action: #selector(menuReveal), node: node))
        menu.addItem(menuItem("复制路径", action: #selector(menuCopyPath), node: node))
        return menu
    }

    private func menuItem(_ title: String, action: Selector, node: DirectoryNode) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = node
        return item
    }

    private func node(from sender: Any?) -> DirectoryNode? {
        (sender as? NSMenuItem)?.representedObject as? DirectoryNode
    }

    @objc private func menuOpenFile(_ sender: NSMenuItem) {
        if let file = node(from: sender)?.file { NSWorkspace.shared.open(file.url) }
    }

    @objc private func menuReveal(_ sender: NSMenuItem) {
        if let node = node(from: sender) { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
    }

    @objc private func menuCopyPath(_ sender: NSMenuItem) {
        if let node = node(from: sender) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(node.url.path, forType: .string)
        }
    }

    // MARK: - DataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        dataRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard dataRows.indices.contains(row) else { return nil }
        let item = dataRows[row]
        let node = item.node

        let cell = tableView.makeView(withIdentifier: RowHostCell.rowID, owner: nil) as? RowHostCell
            ?? makeCell(identifier: RowHostCell.rowID)
        let rowView = DirectoryNodeRow(
            node: node,
            depth: item.depth,
            isExpanded: node.isFolder && isFolderExpanded(node.id),
            onToggleExpand: { [weak self] in
                self?.onToggleExpand(node)
            }
        )
        if let model {
            cell.configure(
                rowView.environmentObject(model).padding(.horizontal, rowHorizontalPadding)
            )
        } else {
            cell.configure(rowView.padding(.horizontal, rowHorizontalPadding))
        }
        return cell
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> RowHostCell {
        let cell = RowHostCell(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: rowHeight))
        cell.identifier = identifier
        return cell
    }
}

// MARK: - Representable

/// AppKit NSTableView 的 SwiftUI 包装：真正虚拟化，只渲染可见行。
/// 勾选等只改 selectedIDs 的操作不替换 dataRows → 不触发 reload，
/// 已可见 cell 里的 hostingView 因订阅 model 自动刷新，离屏 cell 被释放。
struct DirectoryTable: NSViewControllerRepresentable {
    let model: DirectoryAnalysisModel
    let rows: [DirectoryRowItem]
    /// 结构唯一版本号：仅当 tree/展开变化时 +1；勾选不递增 → 不触发 reload
    let revision: Int
    let fontSize: Double
    let isFolderExpanded: (UUID) -> Bool
    let onToggleExpand: (DirectoryNode) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSViewController(context: Context) -> DirectoryTableController {
        let controller = DirectoryTableController()
        controller.model = model
        controller.dataRows = rows
        controller.isFolderExpanded = isFolderExpanded
        controller.onToggleExpand = onToggleExpand
        controller.rowHeight = Self.height(for: fontSize)
        return controller
    }

    func updateNSViewController(_ controller: DirectoryTableController, context: Context) {
        controller.model = model
        if controller.lastRevision != revision {
            controller.dataRows = rows
            controller.lastRevision = revision
        }
        controller.isFolderExpanded = isFolderExpanded
        controller.onToggleExpand = onToggleExpand
        controller.rowHeight = Self.height(for: fontSize)
    }

    static func height(for fontSize: Double) -> CGFloat {
        // 行高固定在两个极端之间随字号线性缩放，留足两行文本 + 内边距
        (fontSize * 2.9 + 4).clamped(40, 56)
    }

    final class Coordinator {}
}

private extension Double {
    func clamped(_ min: Double, _ max: Double) -> Double {
        Swift.min(Swift.max(self, min), max)
    }
}

// MARK: - 可见行标识（用于轻量比较是否结构变化，避免勾选时 O(n) 重新 reload）

extension DirectoryRowItem {
    /// 稳定、便宜的指纹：区分不同节点与展开层级
    var referenceID: String {
        "row:\(node.id.uuidString):d\(depth)"
    }
}