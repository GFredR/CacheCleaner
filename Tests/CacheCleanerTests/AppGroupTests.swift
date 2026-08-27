import XCTest
@testable import CacheCleaner

@MainActor
final class AppGroupTests: XCTestCase {

    func testGroupByBundleID() {
        let model = CacheCleanerModel()
        model.items = [
            CacheItem(url: URL(fileURLWithPath: "/a/c1"), name: "Xcode", category: .application, bundleID: "com.apple.dt.Xcode", size: 100),
            CacheItem(url: URL(fileURLWithPath: "/a/c2"), name: "Xcode", category: .developer, bundleID: "com.apple.dt.Xcode", size: 200),
            CacheItem(url: URL(fileURLWithPath: "/b/c3"), name: "Safari", category: .application, bundleID: "com.apple.Safari", size: 50),
        ]
        XCTAssertEqual(model.appGroups.count, 2, "同 bundle id 应归并成一组")
        let xcode = model.appGroups.first { $0.name == "Xcode" }
        XCTAssertEqual(xcode?.items.count, 2)
        XCTAssertEqual(xcode?.totalSize, 300, "组大小应为两个子项之和")
        XCTAssertNotNil(model.appGroups.first { $0.name == "Safari" })
    }

    // 无 bundleID 时按展示名归并
    func testGroupWithoutBundleIDByDisplayName() {
        let model = CacheCleanerModel()
        model.items = [
            CacheItem(url: URL(fileURLWithPath: "/a/foo"), name: "Foo", category: .system, size: 10),
            CacheItem(url: URL(fileURLWithPath: "/b/foo"), name: "Foo", category: .system, size: 20),
        ]
        XCTAssertEqual(model.appGroups.count, 1)
        XCTAssertEqual(model.appGroups.first?.totalSize, 30)
    }

    func testToggleGroupSelectsAllThenDeselects() {
        let model = CacheCleanerModel()
        let a = CacheItem(url: URL(fileURLWithPath: "/a/c1"), name: "Xcode", category: .application, bundleID: "dt.xcode", size: 100)
        let b = CacheItem(url: URL(fileURLWithPath: "/a/c2"), name: "Xcode", category: .developer, bundleID: "dt.xcode", size: 200)
        model.items = [a, b]
        let group = model.appGroups[0]

        XCTAssertEqual(model.selectionState(group), .none)
        model.toggleGroup(group)
        XCTAssertEqual(model.selectionState(group), .all)
        XCTAssertEqual(model.selectedCount, 2)
        XCTAssertEqual(model.selectedSize, 300)

        model.toggleGroup(group)
        XCTAssertEqual(model.selectionState(group), .none)
        XCTAssertEqual(model.selectedCount, 0)
    }

    // 组内部分勾选 → partial
    func testPartialSelection() {
        let model = CacheCleanerModel()
        let a = CacheItem(url: URL(fileURLWithPath: "/a/c1"), name: "Xcode", category: .application, bundleID: "dt.xcode", size: 100)
        let b = CacheItem(url: URL(fileURLWithPath: "/a/c2"), name: "Xcode", category: .developer, bundleID: "dt.xcode", size: 200)
        model.items = [a, b]
        let group = model.appGroups[0]
        model.toggleSelection(a)
        XCTAssertEqual(model.selectionState(group), .partial)
    }

    func testDisplayModePersists() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "cacheDisplayMode")
        let m1 = CacheCleanerModel()
        XCTAssertEqual(m1.displayMode, .directory, "默认按目录")
        m1.displayMode = .app
        let m2 = CacheCleanerModel()
        XCTAssertEqual(m2.displayMode, .app, "应持久化选择")
        defaults.removeObject(forKey: "cacheDisplayMode")
    }
}