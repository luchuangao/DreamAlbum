import XCTest

final class PhotoFlowTests: XCTestCase {
    let app = XCUIApplication()
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let fullAccess = springboard.buttons.matching(NSPredicate(format: "label IN %@", ["允许完全访问", "Allow Full Access"])).firstMatch
        if fullAccess.waitForExistence(timeout: 5) { fullAccess.tap() }
    }
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func waitEnabled(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 12))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
    }
    func visibleButton(_ identifier: String) -> XCUIElement {
        let query = app.buttons.matching(identifier: identifier)
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            query.allElementsBoundByIndex.contains { $0.isHittable }
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
        return query.allElementsBoundByIndex.first { $0.isHittable }!
    }
    func visiblePhoto() -> XCUIElement {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.photo."))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            query.allElementsBoundByIndex.contains { $0.isHittable }
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
        return query.allElementsBoundByIndex.first { $0.isHittable }!
    }
    @discardableResult
    func readyReviewPhoto() -> XCUIElement {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "review.photo.", "已加载"))
        let photo = query.firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        return photo
    }
    @discardableResult
    func readyPreviewPhoto() -> XCUIElement {
        let photo = app.images.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", "preview.photo.", "已加载")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15))
        return photo
    }
    func goBack() {
        let candidates = app.navigationBars.buttons.allElementsBoundByIndex
        let back = candidates.first { $0.isHittable && (["首页", "Home", "分组", "返回", "Back"].contains($0.label) || $0.identifier == "BackButton") }
        XCTAssertNotNil(back)
        back?.tap()
    }
    func openAllPhotos() { visibleButton("today.all").tap() }
    func launchDailyFixture(reset: Bool = true, empty: Bool = false, failDelete: Bool = false, undatedOnly: Bool = false, cancelDelete: Bool = false, completed: Bool = false, screenshotsOnly: Bool = false, allReviewed: Bool = false, singleScreenshot: Bool = false) {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-dailyInboxFixture"]
        if reset { app.launchArguments.append("-resetDailyFixture") }
        if empty { app.launchArguments.append("-emptyDailyFixture") }
        if failDelete { app.launchArguments.append("-failFixtureDelete") }
        if undatedOnly { app.launchArguments.append("-undatedOnlyFixture") }
        if cancelDelete { app.launchArguments.append("-cancelFixtureDelete") }
        if completed { app.launchArguments.append("-completedDailyFixture") }
        if screenshotsOnly { app.launchArguments.append("-screenshotsOnlyFixture") }
        if allReviewed { app.launchArguments.append("-allReviewedFixture") }
        if singleScreenshot { app.launchArguments.append("-singleScreenshotFixture") }
        app.launch()
    }
    func testCompletedHomeContinuesOlderThenUndatedWithoutRepeating() {
        launchDailyFixture(completed: true)
        XCTAssertTrue(app.staticTexts["today.remaining"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 1 张")
        XCTAssertFalse(app.staticTexts["today.completed"].exists)
        XCTAssertFalse(app.buttons["today.screenshots"].exists)
        capture("pending-older-day-home")
        visibleButton("today.continue").tap()
        XCTAssertEqual(readyReviewPhoto().identifier, "review.photo.yesterday")
        readyReviewPhoto().swipeRight()
        XCTAssertTrue(app.buttons["today.screenshots"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["today.photos"].exists)
        capture("pending-undated-home")
        visibleButton("today.continue").tap()
        XCTAssertEqual(readyReviewPhoto().identifier, "review.photo.unknown")
        readyReviewPhoto().swipeRight()
        XCTAssertTrue(app.staticTexts["today.completed"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["today.completed"].label, "全部已整理")
        XCTAssertFalse(app.buttons["today.continue"].exists)
        capture("all-reviewed-home")
        openAllPhotos(); XCTAssertTrue(visibleButton("library.filters").exists)
    }
    func testEmptyHomeCategoryIsHidden() {
        launchDailyFixture(screenshotsOnly: true, singleScreenshot: true)
        XCTAssertTrue(app.staticTexts["today.remaining"].waitForExistence(timeout: 8))
        // s0 starts reviewed, so the inbox skips to the earlier unreviewed photo.
        XCTAssertTrue(visibleButton("today.photos").exists)
        XCTAssertFalse(app.buttons["today.screenshots"].exists)
        capture("single-pending-photo-home")
    }
    func testCompletedDayCanRestartFromCalendar() {
        launchDailyFixture(allReviewed: true)
        XCTAssertTrue(app.staticTexts["today.completed"].waitForExistence(timeout: 8))
        visibleButton("today.calendar").tap()
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let today = app.buttons["calendar.day." + formatter.string(from: Date())]
        XCTAssertTrue(today.waitForExistence(timeout: 5)); today.tap()
        let restart = app.buttons["calendar.restart"]
        if !restart.isHittable { app.scrollViews.firstMatch.swipeUp() }
        capture("calendar-restart-day")
        visibleButton("calendar.restart").tap()
        XCTAssertEqual(readyReviewPhoto().identifier, "review.photo.p0")
        readyReviewPhoto().swipeLeft()
        visibleButton("关闭整理").tap()
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 23 张")
        XCTAssertEqual(visibleButton("today.pending").label, "待删 1")
        // Restart that day again: prior pending markers must survive.
        visibleButton("today.calendar").tap()
        if !app.buttons["calendar.restart"].isHittable { app.scrollViews.firstMatch.swipeUp() }
        visibleButton("calendar.restart").tap()
        XCTAssertEqual(readyReviewPhoto().identifier, "review.photo.p0")
        visibleButton("关闭整理").tap()
        XCTAssertEqual(visibleButton("today.pending").label, "待删 1")
    }
    func testEnglishCompletionAndCalendarLayout() {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-dream_album.app_language", "english", "-dailyInboxFixture", "-resetDailyFixture", "-allReviewedFixture"]
        app.launch()
        XCTAssertTrue(app.staticTexts["today.completed"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["today.completed"].label, "All caught up")
        XCTAssertFalse(app.buttons["today.photos"].exists)
        capture("english-empty-inbox")
        visibleButton("today.calendar").tap()
        XCTAssertTrue(app.navigationBars["Choose date"].waitForExistence(timeout: 5))
        capture("english-calendar-restart")
        visibleButton("Done").tap()
        openAllPhotos()
        XCTAssertEqual(app.staticTexts["library.selection.title"].label, "All photos")
    }
    func testSortingReminderToggleTimeAndPersistence() {
        launchDailyFixture()
        app.buttons["tab.me"].tap()
        let toggle = app.switches["reminder.toggle"]
        if !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        capture("sorting-reminder-enabled")
        XCTAssertTrue(app.descendants(matching: .any)["reminder.time"].waitForExistence(timeout: 5))
        capture("sorting-reminder-enabled")
        launchDailyFixture(reset: false)
        app.buttons["tab.me"].tap()
        if !app.switches["reminder.toggle"].isHittable { app.swipeUp() }
        XCTAssertEqual(app.switches["reminder.toggle"].value as? String, "1")
        app.switches["reminder.toggle"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertFalse(app.descendants(matching: .any)["reminder.time"].exists)
        capture("sorting-reminder-disabled")
    }
    func testFilterSheetTypesMonthsResetAndRestart() {
        launchDailyFixture()
        openAllPhotos(); visibleButton("library.filters").tap()
        XCTAssertTrue(app.navigationBars["筛选照片"].waitForExistence(timeout: 5))
        capture("filter-panel")
        visibleButton("filter.screenshots").tap()
        visibleButton("filter.done").tap()
        XCTAssertTrue(app.staticTexts["仅屏幕截图"].waitForExistence(timeout: 5))
        XCTAssertTrue(visiblePhoto().identifier.hasPrefix("library.photo.s"))
        visibleButton("library.filters").tap()
        visibleButton("filter.month").tap()
        XCTAssertTrue(app.navigationBars["月份"].waitForExistence(timeout: 5))
        capture("filter-months")
        app.buttons["日期未知"].tap()
        visibleButton("filter.done").tap()
        XCTAssertTrue(app.descendants(matching: .any)["library.photo.unknown"].waitForExistence(timeout: 5))
        visibleButton("library.filters").tap()
        visibleButton("filter.reset").tap()
        visibleButton("重新整理当前范围").tap()
        XCTAssertEqual(readyReviewPhoto().identifier, "review.photo.p0")
        visibleButton("关闭整理").tap()
    }
    func launchHomeDateTaskFixture() {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-dailyInboxFixture", "-resetDailyFixture", "-homeDateTaskFixture"]
        app.launch()
    }
    func testSelectedHomeHasOneProgressAndPendingDescriptionsAreRemoved() {
        launchHomeDateTaskFixture()
        XCTAssertTrue(app.staticTexts["today.remaining"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 1 张")
        XCTAssertEqual(app.staticTexts["today.next"].label, "已整理 1 / 2")
        XCTAssertFalse(app.staticTexts["已完成"].exists)
        XCTAssertFalse(app.staticTexts["左滑待删 · 右滑保留"].exists)
        XCTAssertFalse(app.staticTexts["1 张待整理"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "还剩 1 张")).count, 1)
        XCTAssertTrue(visibleButton("today.photos").exists)
        XCTAssertFalse(app.buttons["today.screenshots"].exists)
        capture("selected-home-date-task")
        visibleButton("today.pending").tap()
        XCTAssertTrue(app.navigationBars["待删清单"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["删除手机原图，画册副本保留。"].exists)
        XCTAssertFalse(app.staticTexts["Live Photo 的动态部分也会删除。"].exists)
        capture("pending-without-descriptions")
    }
    func testCalendarSwipeMonthsAndRestartUsesChosenDate() {
        launchHomeDateTaskFixture()
        visibleButton("today.calendar").tap()
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let older = calendar.date(byAdding: .month, value: -1, to: yesterday)!
        let title = app.buttons["calendar.month"]
        let initial = title.label
        app.scrollViews.firstMatch.swipeRight()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in title.label != initial }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        capture("calendar-swiped-previous")
        app.scrollViews.firstMatch.swipeLeft()
        XCTAssertEqual(title.label, initial)
        // A left swipe cannot advance beyond the current month.
        app.scrollViews.firstMatch.swipeLeft()
        XCTAssertEqual(title.label, initial)
        app.scrollViews.firstMatch.swipeRight()
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        app.buttons["calendar.day." + formatter.string(from: older)].tap()
        visibleButton("完成").tap()
        let label = DateFormatter(); label.locale = Locale(identifier: "zh_CN"); label.dateFormat = "M月d日 EE"
        XCTAssertEqual(visibleButton("today.calendar").value as? String, label.string(from: older))
        visibleButton("today.calendar").tap()
        visibleButton("calendar.next").tap()
        app.buttons["calendar.day." + formatter.string(from: yesterday)].tap()
        visibleButton("calendar.restart").tap()
        XCTAssertEqual(readyReviewPhoto().identifier, "review.photo.dayDone")
        visibleButton("关闭整理").tap()
        XCTAssertEqual(visibleButton("today.calendar").value as? String, label.string(from: yesterday))
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 2 张")
        XCTAssertEqual(app.staticTexts["today.next"].label, "已整理 0 / 2")
        XCTAssertEqual(visibleButton("today.pending").label, "待删 1")
        capture("restart-follows-calendar-date")
    }
    func testHomeArrowOpensScopedBrowserWithPhotoActions() {
        launchDailyFixture()
        visibleButton("today.photos.browse").tap()
        XCTAssertTrue(app.staticTexts["library.selection.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["library.selection.title"].label, "照片")
        XCTAssertTrue(app.staticTexts["12 张"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["library.photo.p6"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["library.photo.p0"].exists)
        capture("home-scope-browser")
        visibleButton("选择").tap(); visiblePhoto().tap()
        XCTAssertFalse(app.staticTexts["横滑或双指拖动可多选"].exists)
        visibleButton("library.action.groups").tap()
        XCTAssertTrue(app.navigationBars["加入分组"].waitForExistence(timeout: 5))
        visibleButton("取消").tap()
        visibleButton("library.action.dreams").tap()
        XCTAssertTrue(app.navigationBars["加入梦想画册"].waitForExistence(timeout: 5))
        visibleButton("取消").tap()
        capture("home-scope-selection")
        visibleButton("library.action.pending").tap()
        visibleButton("library.pending").tap()
        XCTAssertTrue(app.navigationBars["待删清单"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["清空待删清单"].exists)
        capture("pending-without-clear")
        visibleButton("取消待删").tap(); visibleButton("完成").tap()
        visibleButton("完成").tap()
        goBack()
        openAllPhotos()
        XCTAssertTrue(app.descendants(matching: .any)["library.photo.p0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["library.selection.title"].label, "全部照片")
    }
    func testReadOnlyGroupsCanHideAndRestoreWithPreferenceSaved() {
        launchDailyFixture()
        app.buttons["tab.groups"].tap()
        XCTAssertTrue(app.staticTexts["最近项目"].waitForExistence(timeout: 5))
        visibleButton("group.filters").tap()
        visibleButton("隐藏不可编辑分组").tap()
        XCTAssertFalse(app.staticTexts["最近项目"].exists)
        XCTAssertTrue(app.staticTexts["测试分组"].exists)
        XCTAssertEqual(visibleButton("group.filters").value as? String, "仅可编辑")
        capture("groups-editable-only")
        launchDailyFixture(reset: false)
        app.buttons["tab.groups"].tap()
        XCTAssertTrue(app.staticTexts["测试分组"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["最近项目"].exists)
        XCTAssertEqual(visibleButton("group.filters").value as? String, "仅可编辑")
        visibleButton("group.filters").tap()
        visibleButton("隐藏不可编辑分组").tap()
        XCTAssertTrue(app.staticTexts["最近项目"].waitForExistence(timeout: 5))
        XCTAssertEqual(visibleButton("group.filters").value as? String, "全部分组")
        capture("groups-restored-all")
    }
    func testCalendarShowsReviewedProgress() {
        launchDailyFixture()
        visibleButton("today.calendar").tap()
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let todayID = "calendar.day." + formatter.string(from: Date())
        XCTAssertTrue(app.buttons[todayID].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons[todayID].value as? String, "24 张图片，已整理 8 张，整理中")
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let previous = app.buttons["calendar.day." + formatter.string(from: yesterday)]
        if previous.exists { XCTAssertEqual(previous.value as? String, "1 张图片，已整理 0 张，未整理") }
        capture("calendar-partial-and-unreviewed")
        launchDailyFixture(allReviewed: true)
        visibleButton("today.calendar").tap()
        XCTAssertTrue(app.buttons[todayID].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons[todayID].value as? String, "24 张图片，已整理 24 张，已整理")
        capture("calendar-completed")
    }
    func testSystemAlbumExplainsLimitsAndAllowsPhotoActions() {
        launchDailyFixture()
        app.buttons["tab.groups"].tap()
        visibleButton("group.info.readonly").tap()
        XCTAssertTrue(app.alerts["系统相册"].waitForExistence(timeout: 5))
        capture("system-album-info")
        app.alerts["系统相册"].buttons["好"].tap()
        XCTAssertFalse(app.buttons["group.actions.readonly"].exists)
        app.staticTexts["最近项目"].tap()
        visibleButton("选择").tap(); visiblePhoto().tap()
        visibleButton("library.action.pending").tap()
        XCTAssertEqual(visibleButton("library.pending").label, "待删 1")
        capture("system-album-photo-actions")
    }
    func testNativeBrowserHeaderAndSwipeBack() {
        launchDailyFixture()
        openAllPhotos()
        XCTAssertTrue(app.staticTexts["library.selection.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["library.selection.title"].label, "全部照片")
        XCTAssertFalse(app.navigationBars.staticTexts["照片"].exists)
        capture("native-all-photos-header")
        let first = visiblePhoto()
        let before = first.frame.minY
        app.swipeUp()
        XCTAssertTrue(!first.isHittable || first.frame.minY < before - 2)
        XCTAssertTrue(visibleButton("library.filters").exists)
        app.swipeRight()
        XCTAssertTrue(visibleButton("today.all").exists)
        openAllPhotos()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(visibleButton("today.all").exists)
        capture("edge-swipe-returns-home")
    }
    func testSelectionSwipeDoesNotNavigateBack() {
        launchDailyFixture()
        openAllPhotos(); visibleButton("选择").tap(); visiblePhoto().tap()
        app.swipeRight()
        XCTAssertTrue(app.staticTexts["library.selection.title"].label.hasPrefix("已选择"))
        XCTAssertTrue(visibleButton("library.filters").exists)
        visibleButton("完成").tap()
        app.swipeRight()
        XCTAssertTrue(visibleButton("today.all").exists)
    }
    func testReviewShortDragReturnsAndCommittedSwipeCanUndo() {
        launchDailyFixture()
        visibleButton("today.continue").tap()
        let photo = readyReviewPhoto(); let first = photo.identifier
        let from = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = photo.coordinate(withNormalizedOffset: CGVector(dx: 0.56, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: to)
        XCTAssertEqual(readyReviewPhoto().identifier, first)
        readyReviewPhoto().swipeLeft()
        XCTAssertNotEqual(readyReviewPhoto().identifier, first)
        visibleButton("撤销").tap()
        XCTAssertEqual(readyReviewPhoto().identifier, first)
        XCTAssertEqual(visibleButton("review.pending").label, "待删 0")
        capture("swipe-review-with-undo")
    }
    func testTodayInboxScopeAndResume() {
        launchDailyFixture()
        XCTAssertTrue(app.staticTexts["today.remaining"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 16 张")
        XCTAssertTrue(visibleButton("today.continue").isEnabled)
        XCTAssertFalse(app.buttons["截图"].exists)
        capture("daily-inbox")
        visibleButton("today.screenshots").tap()
        XCTAssertFalse(app.sheets["继续上次整理？"].exists)
        readyReviewPhoto()
        XCTAssertTrue(app.descendants(matching: .any)["review.photo.s2"].exists)
        readyReviewPhoto().swipeRight()
        visibleButton("关闭整理").tap()
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 15 张")
        visibleButton("today.photos").tap()
        readyReviewPhoto()
        XCTAssertTrue(app.descendants(matching: .any)["review.photo.p6"].exists)
        visibleButton("关闭整理").tap()
        visibleButton("today.continue").tap()
        readyReviewPhoto()
        XCTAssertTrue(app.descendants(matching: .any)["review.photo.p6"].exists)
        capture("daily-review-resume")
        visibleButton("关闭整理").tap()
        launchDailyFixture(reset: false)
        XCTAssertTrue(app.staticTexts["today.remaining"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 15 张")
        visibleButton("today.calendar").tap()
        XCTAssertTrue(app.navigationBars["选择日期"].waitForExistence(timeout: 5))
        capture("daily-calendar")
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"
        let today = app.buttons["calendar.day." + formatter.string(from: Date())]
        XCTAssertEqual(today.value as? String, "24 张图片，已整理 9 张，整理中")
        let yesterdayDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterday = app.buttons["calendar.day." + formatter.string(from: yesterdayDate)]
        if yesterday.exists { XCTAssertEqual(yesterday.value as? String, "1 张图片，已整理 0 张，未整理"); yesterday.tap() }
        visibleButton("回到今天").tap()
        openAllPhotos()
        XCTAssertTrue(app.buttons["library.filters"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["截图"].exists)
        capture("all-photos-filter")
    }
    func testEmptyTodayUsesNearestUnreviewedDay() {
        launchDailyFixture(empty: true)
        XCTAssertTrue(app.staticTexts["today.remaining"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 1 张")
        XCTAssertTrue(visibleButton("today.photos").exists)
        XCTAssertFalse(app.buttons["today.screenshots"].exists)
        visibleButton("today.continue").tap()
        XCTAssertEqual(readyReviewPhoto().identifier, "review.photo.yesterday")
        readyReviewPhoto().swipeRight()
        XCTAssertTrue(app.buttons["today.screenshots"].waitForExistence(timeout: 8))
        visibleButton("today.continue").tap()
        XCTAssertEqual(readyReviewPhoto().identifier, "review.photo.recentScreenshot")
        visibleButton("关闭整理").tap()
        openAllPhotos(); XCTAssertTrue(visiblePhoto().exists)
    }
    func testUndatedOnlyLibraryOffersReviewAndPending() {
        launchDailyFixture(empty: true, undatedOnly: true)
        XCTAssertTrue(app.staticTexts["today.remaining"].waitForExistence(timeout: 8))
        XCTAssertTrue(visibleButton("today.continue").exists)
        visibleButton("today.pending").tap()
        XCTAssertTrue(app.navigationBars["待删清单"].waitForExistence(timeout: 5))
        visibleButton("完成").tap()
        openAllPhotos(); XCTAssertTrue(visiblePhoto().exists)
    }
    func testGroupCanDeleteOriginalsOrRetainBothWhenDeletionFails() {
        launchDailyFixture(failDelete: true)
        app.buttons["tab.groups"].tap()
        visibleButton("group.actions.editable").tap()
        capture("group-delete-options")
        visibleButton("删除分组及 2 张原图").tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(visibleButton("group.actions.editable").exists)
        app.buttons["tab.photos"].tap()
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 16 张")
        launchDailyFixture()
        app.buttons["tab.groups"].tap()
        visibleButton("group.actions.editable").tap()
        visibleButton("删除分组及 2 张原图").tap()
        XCTAssertTrue(app.staticTexts["最近项目"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["group.actions.editable"].exists)
        XCTAssertTrue(app.alerts.count == 0)
        app.buttons["tab.photos"].tap()
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 16 张")
    }
    func testRemoveFromGroupKeepsOriginalInLibrary() {
        launchDailyFixture()
        app.buttons["tab.groups"].tap()
        XCTAssertTrue(app.staticTexts["测试分组"].waitForExistence(timeout: 5))
        app.staticTexts["测试分组"].tap()
        visibleButton("选择").tap()
        let photo = visiblePhoto(); let removedID = photo.identifier
        photo.tap()
        visibleButton("library.action.groups").tap()
        capture("group-selection-actions")
        visibleButton("移出分组").tap()
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.descendants(matching: .any)[removedID])
        XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 8), .completed)
        XCTAssertEqual(app.staticTexts["library.selection.title"].label, "已选择 0 张")
        app.buttons["tab.photos"].tap()
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 16 张")
    }
    func testFinishingEachHomeCategoryReturnsHomeAndKeepsPending() {
        launchDailyFixture(empty: true)
        visibleButton("today.photos").tap()
        readyReviewPhoto().swipeRight()
        XCTAssertTrue(app.staticTexts["today.remaining"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 1 张")
        XCTAssertFalse(app.staticTexts["整理完成"].exists)
        visibleButton("today.screenshots").tap()
        readyReviewPhoto().swipeLeft()
        XCTAssertEqual(visibleButton("today.pending").label, "待删 1")
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 1 张")
        XCTAssertTrue(visibleButton("today.continue").isEnabled)
        capture("completed-review-returns-home")
    }
    func testFinishingGroupReviewReturnsPhotoHomeAndPopsAllPhotos() {
        launchDailyFixture()
        openAllPhotos()
        app.buttons["tab.groups"].tap()
        XCTAssertTrue(app.staticTexts["测试分组"].waitForExistence(timeout: 5))
        app.staticTexts["测试分组"].tap()
        visibleButton("library.filters").tap()
        visibleButton("重新整理当前范围").tap()
        readyReviewPhoto().swipeLeft()
        readyReviewPhoto().swipeRight()
        XCTAssertEqual(visibleButton("today.pending").label, "待删 1")
        XCTAssertTrue(visibleButton("today.all").isHittable)
        XCTAssertFalse(app.buttons["library.filters"].isHittable)
        capture("group-review-returns-home")
    }
    func testDirectPendingActionAndHomeEntry() {
        launchDailyFixture()
        openAllPhotos(); visibleButton("选择").tap(); visiblePhoto().tap()
        XCTAssertFalse(app.buttons["更多"].exists)
        capture("direct-pending-toolbar")
        visibleButton("library.action.pending").tap()
        XCTAssertEqual(app.staticTexts["library.selection.title"].label, "已选择 0 张")
        visibleButton("library.pending").tap()
        XCTAssertTrue(app.navigationBars["待删清单"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["取消待删"].exists)
        visibleButton("完成").tap(); goBack()
        XCTAssertEqual(visibleButton("today.pending").label, "待删 1")
        capture("home-pending-entry")
        visibleButton("today.pending").tap()
        XCTAssertTrue(app.navigationBars["待删清单"].waitForExistence(timeout: 5))
    }
    func testGroupActionsRenameAndDeleteKeepPhotos() {
        launchDailyFixture()
        app.buttons["tab.groups"].tap()
        visibleButton("group.actions.editable").tap()
        visibleButton("重命名").tap()
        let alert = app.alerts["重命名分组"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let name = alert.textFields.firstMatch
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "旅行")
        alert.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["旅行"].waitForExistence(timeout: 5))
        capture("editable-groups")
        visibleButton("group.actions.editable").tap()
        visibleButton("删除分组（保留照片）").tap()
        XCTAssertFalse(app.buttons["group.actions.editable"].exists)
        XCTAssertFalse(app.buttons["group.actions.readonly"].exists)
        XCTAssertTrue(app.staticTexts["最近项目"].exists)
        XCTAssertTrue(app.alerts.count == 0)
        app.buttons["tab.photos"].tap()
        XCTAssertTrue(app.staticTexts["today.remaining"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["today.remaining"].label, "还剩 16 张")
    }
    private func markFixturePhoto() {
        visibleButton("today.continue").tap()
        XCTAssertFalse(app.buttons["移至待删"].exists)
        XCTAssertFalse(app.buttons["留在相册"].exists)
        XCTAssertFalse(app.staticTexts["标记后需手动删除"].exists)
        readyReviewPhoto().swipeLeft()
        visibleButton("review.pending").tap()
        XCTAssertTrue(app.navigationBars["待删清单"].waitForExistence(timeout: 5))
    }
    func testDeleteSubmitsDirectlyAndFailureKeepsPending() {
        launchDailyFixture(failDelete: true)
        markFixturePhoto()
        visibleButton("删除 1 张原图").tap()
        XCTAssertTrue(app.alerts["删除失败"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts["删除手机照片库原图？"].exists)
        app.alerts["删除失败"].buttons["好"].tap()
        XCTAssertTrue(app.buttons["取消待删"].exists)
        capture("direct-delete-failure")
    }
    func testCancelledDeleteKeepsPendingOpen() {
        launchDailyFixture(cancelDelete: true)
        markFixturePhoto()
        visibleButton("删除 1 张原图").tap()
        waitEnabled(app.buttons["删除 1 张原图"])
        XCTAssertTrue(app.navigationBars["待删清单"].exists)
        XCTAssertTrue(app.buttons["取消待删"].exists)
        XCTAssertTrue(app.alerts.count == 0)
        capture("cancelled-delete-keeps-list")
    }
    func testDeleteSuccessClearsPendingWithoutAppConfirmation() {
        launchDailyFixture()
        markFixturePhoto()
        capture("pending-short-copy")
        visibleButton("删除 1 张原图").tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.navigationBars["待删清单"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 8), .completed)
        XCTAssertEqual(visibleButton("review.pending").label, "待删 0")
        XCTAssertTrue(app.alerts.count == 0)
        capture("delete-success-returns-to-review")
    }
    func testPreviewSwipesAndZoomedPanning() {
        launchDailyFixture()
        openAllPhotos(); visiblePhoto().tap()
        let first = readyPreviewPhoto().identifier
        let preview = app.scrollViews["library.preview"]
        preview.swipeLeft()
        XCTAssertNotEqual(readyPreviewPhoto().identifier, first)
        capture("preview-swipe-next")
        let second = readyPreviewPhoto().identifier
        preview.pinch(withScale: 4, velocity: 1)
        let zoomed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "100%"), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [zoomed], timeout: 5), .completed)
        preview.swipeLeft()
        XCTAssertEqual(readyPreviewPhoto().identifier, second)
        preview.doubleTap()
        let fitted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "100%"), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [fitted], timeout: 5), .completed)
        preview.swipeRight()
        XCTAssertNotEqual(readyPreviewPhoto().identifier, second)
        visibleButton("完成").tap()
        XCTAssertEqual(visibleButton("library.pending").label, "待删 1")
    }
    func testGroupDestinationFitsAndKeyboardCanDismiss() {
        launchDailyFixture()
        visibleButton("today.continue").tap(); readyReviewPhoto()
        visibleButton("review.groups").tap(); visibleButton("review.destination.groups").tap()
        XCTAssertTrue(app.navigationBars["加入分组"].waitForExistence(timeout: 5))
        let cancel = visibleButton("取消")
        XCTAssertGreaterThanOrEqual(cancel.frame.minX, 0)
        XCTAssertLessThanOrEqual(cancel.frame.maxX, app.frame.width)
        let name = app.textFields["分组名称"]
        XCTAssertGreaterThanOrEqual(name.frame.minX, 0)
        XCTAssertLessThanOrEqual(name.frame.maxX, app.frame.width)
        capture("group-destination-full-screen")
        name.tap(); name.typeText("周末")
        capture("group-destination-keyboard")
        visibleButton("完成").tap()
        visibleButton("group.destination.editable").tap()
        XCTAssertTrue(app.buttons["关闭整理"].waitForExistence(timeout: 8))
        visibleButton("关闭整理").tap()
        app.buttons["tab.groups"].tap()
        XCTAssertTrue(app.staticTexts["3 张"].waitForExistence(timeout: 5))
    }
    func testNativeSelectionAndStableGrid() {
        openAllPhotos()
        let photo = visiblePhoto()
        let before = photo.frame
        visibleButton("选择").tap()
        XCTAssertEqual(photo.frame.minY, before.minY, accuracy: 2)
        photo.tap()
        XCTAssertEqual(photo.value as? String, "已选择")
        XCTAssertEqual(app.staticTexts["library.selection.title"].label, "已选择 1 张")
        photo.tap()
        XCTAssertEqual(app.staticTexts["library.selection.title"].label, "已选择 0 张")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "library.photo.")).allElementsBoundByIndex.filter {
            $0.isHittable && abs($0.frame.minY - photo.frame.minY) < 2
        }.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertGreaterThanOrEqual(row.count, 3)
        let start = row[0].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = row[2].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertEqual(app.staticTexts["library.selection.title"].label, "已选择 3 张")
        capture("native-range-selection")
        visibleButton("全选").tap()
        XCTAssertTrue(visibleButton("取消全选").exists)
        visibleButton("取消全选").tap()
        XCTAssertEqual(app.staticTexts["library.selection.title"].label, "已选择 0 张")
        visibleButton("完成").tap()
        visiblePhoto().press(forDuration: 0.5)
        XCTAssertEqual(app.staticTexts["library.selection.title"].label, "已选择 1 张")
        visibleButton("完成").tap()
        visiblePhoto().tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.scrollViews["library.preview"].exists)
        app.scrollViews["library.preview"].doubleTap()
        capture("photo-preview")
        visibleButton("完成").tap()
    }
    func testAppearanceSelectionAudit() {
        launchDailyFixture()
        app.buttons["tab.me"].tap()
        XCTAssertTrue(app.staticTexts["照片管理"].waitForExistence(timeout: 5))
        capture("audit-me")
        app.buttons["tab.photos"].tap()
        capture("audit-photo-home")
        openAllPhotos()
        visibleButton("选择").tap()
        visiblePhoto().tap()
        capture("audit-selected-photo")
        app.buttons["tab.groups"].tap()
        capture("audit-groups")
        app.buttons["tab.dreams"].tap()
        capture("audit-dreams")
        let cover = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "已保存独立副本")).firstMatch
        if cover.waitForExistence(timeout: 3), cover.isHittable {
            cover.tap()
            XCTAssertTrue(app.buttons["描述操作"].waitForExistence(timeout: 5))
            capture("audit-dream-detail")
            app.swipeUp()
            capture("audit-dream-detail-form")
            app.buttons["dream.actions"].tap()
            visibleButton("分享相册").tap()
            XCTAssertTrue(app.navigationBars["预览分享图"].waitForExistence(timeout: 10))
            capture("audit-share-poster")
        }
    }
    func testEnglishLayoutAndNavigation() {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-dream_album.app_language", "english"]
        app.launch()
        waitEnabled(app.buttons["today.all"])
        capture("english-today")
        openAllPhotos()
        waitEnabled(app.buttons["Review"])
        capture("english-photos")
        app.buttons["tab.dreams"].tap()
        XCTAssertTrue(app.staticTexts["Dream albums"].firstMatch.waitForExistence(timeout: 5))
        capture("english-dream-gallery")
    }
    func testReviewUndoPendingCancelAndNavigation() {
        // Reset only the simulator's local marks; never submit original deletion.
        visibleButton("today.pending").tap()
        if app.buttons["清空待删清单"].waitForExistence(timeout: 1) { visibleButton("清空待删清单").tap() }
        visibleButton("完成").tap()
        openAllPhotos()
        let organize = app.buttons["整理"]
        XCTAssertTrue(organize.waitForExistence(timeout: 15))
        waitEnabled(organize)
        capture("photos-home")
        visibleButton("library.filters").tap()
        visibleButton("重新整理当前范围").tap()
        readyReviewPhoto()
        capture("review-quiet-controls")
        readyReviewPhoto().swipeLeft()
        let undo = app.buttons["撤销"].firstMatch
        waitEnabled(undo); undo.tap()
        readyReviewPhoto().swipeLeft()
        readyReviewPhoto().swipeRight()
        visibleButton("review.pending").tap()
        XCTAssertTrue(app.navigationBars["待删清单"].waitForExistence(timeout: 5))
        capture("pending-originals-confirmation")
        // Direct-delete behavior is tested with the isolated fixture below.
        // Never delete originals from the persistent PhotoKit test library.
        XCTAssertTrue(app.buttons["取消待删"].exists)
        app.buttons["取消待删"].tap()
        visibleButton("完成").tap()
        app.buttons["关闭整理"].tap()
        app.buttons["tab.groups"].tap()
        XCTAssertTrue(app.buttons["新建分组"].waitForExistence(timeout: 5))
        app.buttons["新建分组"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let groupName = "测试分组" + String(UUID().uuidString.prefix(4))
        name.tap(); name.typeText(groupName)
        app.alerts.buttons["创建"].tap()
        // System modification permission may be requested on the first transaction.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["允许", "好", "Allow", "OK"])).firstMatch.tap()
        }
        for _ in 0..<10 {
            if app.staticTexts[groupName].exists && app.staticTexts[groupName].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts[groupName].waitForExistence(timeout: 8))
        capture("system-groups")
        app.staticTexts[groupName].tap()
        app.buttons["添加照片"].tap()
        let photo = visiblePhoto()
        XCTAssertTrue(photo.waitForExistence(timeout: 5)); photo.tap()
        visibleButton("添加 1").tap()
        XCTAssertTrue(app.buttons["选择"].waitForExistence(timeout: 8))
        visibleButton("选择").tap()
        visiblePhoto().tap()
        capture("group-selected-photo")
        let addToDream = app.buttons["library.action.dreams"]
        waitEnabled(addToDream)
        addToDream.tap()
        capture("dream-import-sheet")
        let albumName = app.textFields["画册名称（最多12字）"]
        XCTAssertTrue(albumName.waitForExistence(timeout: 5))
        albumName.tap(); albumName.typeText("海边旅行")
        app.buttons["保存图片副本"].tap()
        let commit = app.buttons["加入梦想画册"].firstMatch
        waitEnabled(commit); commit.tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 8))
        goBack()
        app.buttons["tab.dreams"].tap()
        XCTAssertTrue(app.staticTexts["梦想画册"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["海边旅行"].waitForExistence(timeout: 8))
        capture("dream-gallery")
        app.buttons["tab.me"].tap()
        XCTAssertTrue(app.staticTexts["照片管理"].waitForExistence(timeout: 5))
    }
}
