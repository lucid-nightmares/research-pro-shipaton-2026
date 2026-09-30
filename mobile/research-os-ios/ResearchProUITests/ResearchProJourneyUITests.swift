import XCTest

/// Actual native UI interactions, isolated only by a Debug storage namespace.
/// No local entitlement fixtures or user-data reset. Provider transactions
/// require the explicit opt-in and actual Test Store modal below.
final class ResearchProJourneyUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["RESEARCH_PRO_UI_TEST_SESSION"] = ProcessInfo.processInfo.environment["RESEARCH_PRO_UI_FIXED_SESSION"] ?? UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
    }
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func reveal(_ target: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<10 {
            if target.exists && target.isHittable {
                let bounds = target.frame
                if bounds.width > 0 && bounds.height > 0 &&
                    app.frame.contains(CGPoint(x: bounds.midX, y: bounds.midY)) { return }
            }
            app.swipeUp()
        }
        capture("control-not-visible")
        print("UI_DIAGNOSTIC \(app.debugDescription)")
        XCTAssertTrue(target.waitForExistence(timeout: 4) && target.isHittable, "Expected accessible control: \(target)", file: file, line: line)
    }
    private func dismissKeyboard() {
        if app.keyboards.firstMatch.exists {
            let done = element("dismiss-keyboard")
            if done.waitForExistence(timeout: 2) { done.tap() }
        }
    }
    private func tap(_ target: XCUIElement) { dismissKeyboard(); reveal(target); target.tap() }
    private func turnOn(_ toggle: XCUIElement) {
        dismissKeyboard()
        reveal(toggle)
        if toggle.value as? String != "1" { toggle.tap() }
        let enabled = NSPredicate(format: "value == %@", "1")
        if !enabled.evaluate(with: toggle) {
            // Target the visible control after the keyboard has resigned focus.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        expectation(for: enabled, evaluatedWith: toggle)
        waitForExpectations(timeout: 4)
    }
    private func fill(_ target: XCUIElement, _ text: String, replacing: Bool = false) {
        dismissKeyboard()
        reveal(target)
        target.tap()
        if replacing, let value = target.value as? String, !value.isEmpty {
            target.tap(withNumberOfTaps: 3, numberOfTouches: 1)
            if app.menuItems["Select All"].waitForExistence(timeout: 1) { app.menuItems["Select All"].tap() }
            else if app.buttons["Select All"].exists { app.buttons["Select All"].tap() }
            else { target.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count + 5)) }
        }
        target.typeText(text)
    }
    private func capture(_ name: String, nativeCapture: Bool = false) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        // Keep original screenshots available even if simulator test-session
        // cleanup prevents Xcode from finishing its result bundle.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ResearchPro-\(name).png")
        do { try screenshot.pngRepresentation.write(to: url, options: .atomic); print("UI_SCREENSHOT \(url.path)") }
        catch { print("UI_SCREENSHOT_WRITE_FAILED \(error.localizedDescription)") }
        // An external simctl watcher can preserve native screen pixels while
        // this test-only hold keeps the same screen visible. No app state changes.
        if nativeCapture { Thread.sleep(forTimeInterval: 2) }
    }
    private func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }

    func testFreshUserProjectRepairRelaunchDefenseAndExport() throws {
        app.launch()
        XCTAssertTrue(element("create-project").waitForExistence(timeout: 15))
        capture("01-fresh-library")
        tap(element("create-project"))
        fill(element("project-title"), "UI research journey")
        fill(element("research-question"), "What changed in this observed class?")
        tap(element("confirm-create-project"))
        tap(element("capture-evidence"))
        fill(element("source-title"), "Classroom observation")
        fill(element("source-excerpt"), "One observed classroom had higher scores with music. Order was not randomized; this does not establish a causal effect.")
        tap(element("save-source"))
        XCTAssertTrue(app.staticTexts["Classroom observation"].waitForExistence(timeout: 5))
        tap(element("add-claim"))
        fill(element("claim-text"), "Music definitely improves recall for all students.")
        let sourceSwitch = app.switches["Classroom observation"]
        turnOn(sourceSwitch)
        tap(element("save-claim"))
        tap(app.staticTexts["Music definitely improves recall for all students."])
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "This phrase asserts strong certainty")).firstMatch.waitForExistence(timeout: 5))
        capture("02-real-user-finding")
        tap(element("repair-wording"))
        fill(element("repair-after"), "Scores were higher in this observed class.", replacing: true)
        fill(element("repair-reason"), "Limit the conclusion to the exact classroom source.")
        tap(app.buttons["Preview repair"])
        capture("03-human-repair-preview")
        tap(element("accept-repair"))
        XCTAssertTrue(app.staticTexts["Scores were higher in this observed class."].waitForExistence(timeout: 5))
        app.terminate()
        app.launch() // Same isolated workspace; no data seeding on relaunch.
        tap(app.staticTexts["UI research journey"])
        tap(app.staticTexts["Scores were higher in this observed class."])
        tap(element("start-standard-defense"))
        XCTAssertTrue(element("defense-answer-basis").waitForExistence(timeout: 10))
        for question in ["basis", "change", "limit"] {
            fill(element("defense-answer-" + question), "The classroom note supports only a bounded observation.")
        }
        turnOn(app.switches["Classroom observation"])
        fill(app.descendants(matching: .any).matching(identifier: "defense-limitation").firstMatch, "One class and nonrandom order.")
        tap(element("save-defense"))
        XCTAssertTrue(app.buttons["Answers saved"].waitForExistence(timeout: 5))
        capture("04-saved-defense")
        back(); back()
        tap(element("prepare-pack"))
        XCTAssertTrue(app.buttons["Share readable brief"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share reimportable archive"].exists)
        capture("05-export-ready")
    }

    func testSampleImpactPreviewCancelCommitAndHistory() throws {
        app.launch()
        tap(element("try-sample"))
        XCTAssertTrue(app.staticTexts["Synthetic sample"].waitForExistence(timeout: 5))
        capture("sample-native-project")
        tap(app.staticTexts["Invented observation table"])
        tap(element("preview-exclusion"))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 affected claims · 1 unchanged claims")).firstMatch.waitForExistence(timeout: 5))
        capture("sample-impact-preview")
        tap(app.buttons["Close preview"])
        fill(element("source-decision-reason"), "Review the source origin before relying on it.")
        dismissKeyboard()
        tap(app.buttons["Exclude source…"])
        XCTAssertTrue(app.buttons["Confirm evidence change"].waitForExistence(timeout: 5))
        capture("sample-confirm-evidence-dialog")
        if !app.buttons["Cancel"].exists { print("UI_DIALOG_DIAGNOSTIC \(app.debugDescription)") }
        tap(app.buttons["Cancel"])
        XCTAssertTrue(app.buttons["Exclude source…"].exists)
        tap(app.buttons["Exclude source…"])
        tap(app.buttons["Confirm evidence change"])
        for _ in 0..<4 { app.swipeDown() }
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Source snapshot v2")).firstMatch.waitForExistence(timeout: 5))
        back()
        tap(app.staticTexts["Both conditions used the same classroom in this invented example."])
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "No rule findings.")).firstMatch.waitForExistence(timeout: 5))
        capture("sample-unrelated-claim-preserved")
    }

    func testLargeTypeNavigation() throws {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(element("create-project").waitForExistence(timeout: 15))
        capture("accessibility-large-library")
        tap(element("try-sample"))
        tap(element("capture-evidence"))
        reveal(element("source-title"))
        XCTAssertTrue(element("source-title").exists)
        capture("accessibility-large-capture")
        tap(app.buttons["Cancel"])
        XCTAssertTrue(element("capture-evidence").exists)
    }

    /// Run explicitly against a reviewed Test Store configuration. Exclude this
    /// method from the ordinary free/offline suite with -skip-testing, then use
    /// -only-testing for the provider evidence run. It never taps purchase or restore.
    func testOptInRealRevenueCatTestStorePaywallReadOnly() throws {
        app.launch()
        XCTAssertTrue(element("create-project").waitForExistence(timeout: 15))
        capture("provider-normal-home", nativeCapture: true)
        tap(app.buttons["Research Pro Plus"])
        let environment = element("subscriptionEnvironment")
        XCTAssertTrue(environment.waitForExistence(timeout: 10))
        try XCTSkipUnless(environment.label.contains("RevenueCat Test Store"),
                          "An explicitly configured RevenueCat Test Store build is required.")

        let plans = app.buttons.matching(NSPredicate(format:
            "label == %@ OR label == %@", "Explore Research Pro Plus", "View plan options")).firstMatch
        reveal(plans)
        // The production controller enables this only after its real provider
        // offering passes the monthly/annual/entitlement contract checks.
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: plans)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 40), .completed,
                       "The real Test Store offering did not load and pass review.")
        capture("provider-test-store-offering-ready", nativeCapture: true)
        tap(plans)
        let close = app.buttons["Close Plus plans"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        let restore = element("paywall-restore-purchases")
        let restoreReady = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: restore)
        let restoreResult = XCTWaiter.wait(for: [restoreReady], timeout: 10)
        capture("provider-native-paywall-open", nativeCapture: true)
        if restoreResult != .completed { print("PAYWALL_ACCESSIBILITY_DIAGNOSTIC \(app.debugDescription)") }
        XCTAssertEqual(restoreResult, .completed,
                       "The app-owned Restore control must remain visible on the native paywall.")
        XCTAssertTrue(element("native-subscription-paywall").exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No Paywall configured")).firstMatch.exists)
        let monthly = element("native-plan-$rc_monthly")
        let annual = element("native-plan-$rc_annual")
        reveal(monthly)
        XCTAssertTrue(monthly.label.contains("Monthly") && monthly.label.contains("$"),
                      "The actual monthly package must show its localized store price.")
        tap(monthly)
        XCTAssertTrue(monthly.isSelected)
        capture("provider-native-monthly-selected", nativeCapture: true)
        reveal(annual)
        XCTAssertTrue(annual.label.contains("Annual") && annual.label.contains("$"),
                      "The actual annual package must show its localized store price.")
        tap(annual)
        XCTAssertTrue(annual.isSelected)
        let purchase = element("confirm-native-purchase")
        reveal(purchase)
        XCTAssertTrue(purchase.label.contains("Continue with Test Store"))
        XCTAssertTrue(purchase.isEnabled)
        let renewal = element("native-paywall-renewal-terms")
        reveal(renewal)
        XCTAssertTrue(renewal.label.contains("1 year") && renewal.label.contains("Renews automatically"))
        print("PROVIDER_NATIVE_PLANS monthly=\(monthly.label) annual=\(annual.label) renewal=\(renewal.label)")
        capture("provider-native-annual-terms-close-restore", nativeCapture: true)
        // Purchase and restore are deliberately never tapped.
        tap(close)
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        capture("provider-test-store-paywall-closed", nativeCapture: true)

        // Enabled only by this explicit Debug/Test Store build override after
        // account-holder review. The shipped default remains unreviewed.
        let manage = app.buttons["Manage subscription"]
        reveal(manage)
        XCTAssertTrue(manage.isEnabled, "This explicit review run needs RC_CUSTOMER_CENTER_REVIEWED=YES.")
        tap(manage)
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15))
        let finishedLoading = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.progressIndicators.firstMatch)
        let loadResult = XCTWaiter.wait(for: [finishedLoading], timeout: 20)
        print("CUSTOMER_CENTER_LOADING_FINISHED \(loadResult == .completed)")
        print("CUSTOMER_CENTER_OBSERVED \(app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | "))")
        // Customer Center can show an anonymous customer identifier. These
        // original captures stay private; publication uses a sanitized observation.
        capture("PRIVATE-provider-customer-center-observed", nativeCapture: true)
        tap(done)
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        capture("provider-customer-center-dismissed", nativeCapture: true)
    }

    /// Explicitly authorized post-purchase check. The test runner variable is
    /// required so ordinary suites never invoke Restore. It does not grant access.
    func testOptInAuthorizedTestStoreActiveRelaunchRestoreAndAdvanced() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RESEARCH_PRO_PROVIDER_LIFECYCLE_AUTHORIZED"] == "YES",
                          "Requires explicit permission to verify the existing human purchase and invoke Restore.")
        app.launch()
        XCTAssertTrue(element("create-project").waitForExistence(timeout: 15))
        tap(app.buttons["Research Pro Plus"])
        let environment = element("subscriptionEnvironment")
        XCTAssertTrue(environment.waitForExistence(timeout: 10))
        XCTAssertTrue(environment.label.contains("RevenueCat Test Store"))
        tap(app.buttons["Refresh status"])
        for _ in 0..<5 { app.swipeDown() }
        capture("authorized-provider-before-active-check", nativeCapture: true)
        let active = app.staticTexts["Research Pro Plus — Test Store"]
        XCTAssertTrue(active.waitForExistence(timeout: 30), "The actual existing Test Store entitlement must be active.")
        for _ in 0..<5 { app.swipeDown() }
        capture("authorized-provider-active-current", nativeCapture: true)

        // The user explicitly authorized Restore after completing the purchase.
        tap(app.buttons["Restore purchases"])
        for _ in 0..<5 { app.swipeDown() }
        let restored = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@",
            "Restore completed. RevenueCat reports active Plus access in this environment.")).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 30))
        XCTAssertTrue(active.exists)
        for _ in 0..<5 { app.swipeDown() }
        capture("authorized-provider-restore-active", nativeCapture: true)
        print("AUTHORIZED_PROVIDER_RESTORE actual SDK Restore returned active Test Store Plus")

        app.terminate()
        app.launch() // Same SDK installation and research namespace; no clearing.
        tap(app.buttons["Research Pro Plus"])
        XCTAssertTrue(environment.waitForExistence(timeout: 10))
        tap(app.buttons["Refresh status"])
        for _ in 0..<5 { app.swipeDown() }
        XCTAssertTrue(active.waitForExistence(timeout: 30))
        for _ in 0..<5 { app.swipeDown() }
        capture("authorized-provider-relaunch-active", nativeCapture: true)
        app.terminate(); app.launch()

        // Two real user-created projects exercise capacity using actual access.
        // The UUID namespace isolates authored QA research only, never SDK identity.
        for title in ["Provider verification A", "Provider verification B"] {
            tap(element("create-project"))
            fill(element("project-title"), title)
            fill(element("research-question"), "What does this verification note document?")
            tap(element("confirm-create-project"))
            XCTAssertTrue(element("capture-evidence").waitForExistence(timeout: 10))
            if title.hasSuffix(" A") { back() }
        }
        tap(element("capture-evidence"))
        fill(element("source-title"), "Authored verification note")
        fill(element("source-excerpt"), "This authored note documents a simulator verification example. It makes no scientific result claim.")
        tap(element("save-source"))
        tap(element("add-claim"))
        fill(element("claim-text"), "This note documents the verification example.")
        turnOn(app.switches["Authored verification note"])
        tap(element("save-claim"))
        tap(app.staticTexts["This note documents the verification example."])
        tap(app.buttons["Start advanced defense"])
        XCTAssertTrue(element("defense-answer-basis").waitForExistence(timeout: 30), "An authorized premium session must open after fresh provider validation.")
        let sourceQuestion = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "defense-answer-source-")).firstMatch
        capture("authorized-provider-advanced-session", nativeCapture: true)
        fill(element("defense-answer-basis"), "The exact note describes this example.")
        fill(element("defense-answer-change"), "A revised note would change the claim.")
        fill(element("defense-answer-limit"), "This is only a verification example.")
        dismissKeyboard()
        reveal(sourceQuestion)
        XCTAssertTrue(sourceQuestion.exists)
        fill(sourceQuestion, "Without this note the claim has no basis.")
        fill(element("defense-answer-contradiction"), "No independent supporting record is supplied.")
        fill(element("defense-answer-alternative"), "The note may be incomplete.")
        fill(element("defense-answer-scope"), "Only this authored verification note.")
        turnOn(app.switches["Authored verification note"])
        fill(element("defense-limitation"), "This checks app behavior, not a scientific claim.")
        tap(element("save-defense"))
        XCTAssertTrue(app.buttons["Answers saved"].waitForExistence(timeout: 5))
        capture("authorized-provider-advanced-saved", nativeCapture: true)
        print("AUTHORIZED_PROVIDER_ADVANCED actual entitlement allowed second project and source-specific seven-question session; answers saved")
        app.terminate(); app.launch()
        tap(app.staticTexts["Provider verification B"])
        tap(app.staticTexts["This note documents the verification example."])
        tap(app.staticTexts["Advanced defense"])
        XCTAssertTrue(element("defense-answer-basis").waitForExistence(timeout: 5))
        XCTAssertEqual(element("defense-answer-basis").value as? String, "The exact note describes this example.")
        capture("authorized-provider-saved-history-relaunch", nativeCapture: true)
    }


    /// Explicit film capture uses the same canonical sample and user operations.
    /// It never invokes purchase, Restore, or a local entitlement override.
    func testOptInJudgeSampleRepairImpactDefenseAndExportCapture() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RESEARCH_PRO_JUDGE_CAPTURE_AUTHORIZED"] == "YES",
                          "Run explicitly to record the native sample journey.")
        app.launch()
        XCTAssertTrue(element("create-project").waitForExistence(timeout: 15))
        capture("judge-01-native-home", nativeCapture: true)
        tap(element("try-sample"))
        XCTAssertTrue(app.staticTexts["Synthetic sample"].waitForExistence(timeout: 5))
        capture("judge-02-synthetic-project", nativeCapture: true)
        tap(app.staticTexts["Instrumental music improves recall for all students."])
        capture("judge-03-original-claim-findings", nativeCapture: true)
        tap(element("repair-wording"))
        let bounded = "In this invented class, music scores were 4.17 percentage points higher."
        fill(element("repair-after"), bounded, replacing: true)
        fill(element("repair-reason"), "Limit the description to twelve invented observations; condition order was not randomized.")
        tap(app.buttons["Preview repair"])
        capture("judge-04-human-repair-preview", nativeCapture: true)
        tap(element("accept-repair"))
        XCTAssertTrue(app.staticTexts[bounded].waitForExistence(timeout: 5))
        capture("judge-05-confirmed-bounded-claim", nativeCapture: true)
        back()
        tap(app.staticTexts["Invented observation table"])
        tap(element("preview-exclusion"))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "1 affected claims · 1 unchanged claims")).firstMatch.waitForExistence(timeout: 5))
        capture("judge-06-impact-preview", nativeCapture: true)
        tap(app.buttons["Close preview"])
        back()
        tap(app.staticTexts[bounded])
        tap(element("start-standard-defense"))
        XCTAssertTrue(element("defense-answer-basis").waitForExistence(timeout: 10))
        capture("judge-07-standard-defense-questions", nativeCapture: true)
        fill(element("defense-answer-basis"), "The invented table totals 78 of 120 in quiet and 83 of 120 with music.")
        fill(element("defense-answer-change"), "Different scores or a randomized comparison could change the interpretation.")
        fill(element("defense-answer-limit"), "Invented data and nonrandom order cannot support a causal population claim.")
        turnOn(app.switches["Invented observation table"])
        fill(element("defense-limitation"), "Only twelve invented observations; no causal or population inference.")
        tap(element("save-defense"))
        XCTAssertTrue(app.buttons["Answers saved"].waitForExistence(timeout: 5))
        capture("judge-08-answers-citation-limitation-saved", nativeCapture: true)
        back()
        tap(app.buttons["Start advanced defense"])
        XCTAssertTrue(element("defense-answer-basis").waitForExistence(timeout: 30), "Actual provider access must authorize this advanced session.")
        capture("judge-09-advanced-defense-open", nativeCapture: true)
        let advancedBasis = "The invented table totals 78 of 120 in quiet and 83 of 120 with music."
        fill(element("defense-answer-basis"), advancedBasis)
        fill(element("defense-answer-change"), "Different scores or a randomized comparison could change the interpretation.")
        fill(element("defense-answer-limit"), "Invented data and nonrandom order cannot establish a causal effect.")
        let sourceQuestion = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "defense-answer-source-")).firstMatch
        dismissKeyboard()
        reveal(sourceQuestion)
        XCTAssertTrue(sourceQuestion.exists)
        capture("judge-10-advanced-source-specific-question", nativeCapture: true)
        fill(sourceQuestion, "Without the invented table, the 4.17 percentage point comparison loses its basis.")
        fill(element("defense-answer-contradiction"), "No independent contradictory source is supplied; the nonrandom order limits interpretation.")
        fill(element("defense-answer-alternative"), "Practice or condition order could explain the difference.")
        fill(element("defense-answer-scope"), "Only these twelve invented paired observations.")
        dismissKeyboard()
        capture("judge-11-advanced-alternatives-and-scope", nativeCapture: true)
        turnOn(app.switches["Invented observation table"])
        fill(element("defense-limitation"), "Only twelve invented observations; no causal or population inference.")
        tap(element("save-defense"))
        XCTAssertTrue(app.buttons["Answers saved"].waitForExistence(timeout: 5))
        capture("judge-12-advanced-exact-answers-saved", nativeCapture: true)
        app.terminate(); app.launch()
        tap(app.staticTexts["Music and recall — synthetic sample"])
        tap(app.staticTexts[bounded])
        tap(app.staticTexts["Advanced defense"])
        XCTAssertTrue(element("defense-answer-basis").waitForExistence(timeout: 10))
        XCTAssertEqual(element("defense-answer-basis").value as? String, advancedBasis)
        capture("judge-13-advanced-history-after-relaunch", nativeCapture: true)
        back(); back()
        tap(element("prepare-pack"))
        XCTAssertTrue(app.buttons["Share readable brief"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Share reimportable archive"].exists)
        capture("judge-14-readable-reimportable-pack-ready", nativeCapture: true)
    }


    /// Authorized zero-charge provider test transaction; never an Apple purchase.
    /// A separate opt-in is required and both environment and official SDK modal
    /// must identify Test Store before the valid-test-transaction action is used.
    func testOptInAuthorizedZeroChargeTestStoreAnnualPurchase() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RESEARCH_PRO_ZERO_CHARGE_TEST_PURCHASE_AUTHORIZED"] == "YES",
                          "Requires explicit authorization for a zero-charge RevenueCat Test Store transaction.")
        app.launch()
        tap(app.buttons["Research Pro Plus"])
        let environment = element("subscriptionEnvironment")
        XCTAssertTrue(environment.waitForExistence(timeout: 10))
        XCTAssertTrue(environment.label.contains("RevenueCat Test Store") && environment.label.contains("no real charge"))
        let plans = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Explore Research Pro Plus", "View plan options")).firstMatch
        tap(plans)
        let annual = element("native-plan-$rc_annual")
        tap(annual)
        XCTAssertTrue(annual.isSelected)
        // iOS 27 may report an offscreen ScrollView button as hittable.
        // Put the annual price and purchase button visibly inside the viewport.
        app.swipeUp()
        let purchase = element("confirm-native-purchase")
        reveal(purchase)
        XCTAssertTrue(purchase.label.contains("Continue with Test Store") && purchase.isEnabled)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No real payment is charged.")).firstMatch.exists)
        XCTAssertTrue(app.frame.contains(CGPoint(x: purchase.frame.midX, y: purchase.frame.midY)),
                      "The actual Continue button must be on screen before interaction.")
        capture("authorized-annual-plan-before-test-transaction", nativeCapture: true)
        tap(purchase)
        let modal = app.alerts["Test Store Purchase"]
        XCTAssertTrue(modal.waitForExistence(timeout: 15), "Never continue unless the actual SDK identifies its Test Store modal.")
        XCTAssertTrue(modal.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "This is a test purchase and should only be used during development.")).firstMatch.exists)
        XCTAssertTrue(modal.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "research_pro_plus_yearly")).firstMatch.exists)
        capture("authorized-official-test-store-purchase-modal", nativeCapture: true)
        modal.buttons["Test valid purchase"].tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Close Plus plans"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 30), .completed)
        for _ in 0..<5 { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["Research Pro Plus — Test Store"].waitForExistence(timeout: 15))
        capture("authorized-annual-test-store-active", nativeCapture: true)
        print("AUTHORIZED_ZERO_CHARGE_ANNUAL official RevenueCat Test Store valid test purchase completed; production and StoreKit purchase not invoked")
    }

    func testOptInAuthorizedZeroChargeTestStoreMonthlyPurchase() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RESEARCH_PRO_ZERO_CHARGE_TEST_PURCHASE_AUTHORIZED"] == "YES",
                          "Requires explicit authorization for a zero-charge RevenueCat Test Store transaction.")
        app.launch()
        tap(app.buttons["Research Pro Plus"])
        let environment = element("subscriptionEnvironment")
        XCTAssertTrue(environment.waitForExistence(timeout: 10))
        XCTAssertTrue(environment.label.contains("RevenueCat Test Store") && environment.label.contains("no real charge"))
        let plans = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Explore Research Pro Plus", "View plan options")).firstMatch
        tap(plans)
        let monthly = element("native-plan-$rc_monthly")
        tap(monthly)
        XCTAssertTrue(monthly.isSelected)
        // iOS 27 may report an offscreen ScrollView button as hittable.
        // Put the monthly price and purchase button visibly inside the viewport.
        app.swipeUp()
        let purchase = element("confirm-native-purchase")
        reveal(purchase)
        XCTAssertTrue(purchase.label.contains("Continue with Test Store") && purchase.isEnabled)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No real payment is charged.")).firstMatch.exists)
        XCTAssertTrue(app.frame.contains(CGPoint(x: purchase.frame.midX, y: purchase.frame.midY)),
                      "The actual Continue button must be on screen before interaction.")
        capture("authorized-monthly-plan-before-test-transaction", nativeCapture: true)
        tap(purchase)
        let modal = app.alerts["Test Store Purchase"]
        XCTAssertTrue(modal.waitForExistence(timeout: 15), "Never continue unless the actual SDK identifies its Test Store modal.")
        XCTAssertTrue(modal.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "This is a test purchase and should only be used during development.")).firstMatch.exists)
        XCTAssertTrue(modal.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "research_pro_plus_monthly")).firstMatch.exists)
        capture("authorized-official-test-store-purchase-modal", nativeCapture: true)
        modal.buttons["Test valid purchase"].tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["Close Plus plans"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 30), .completed)
        for _ in 0..<5 { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["Research Pro Plus — Test Store"].waitForExistence(timeout: 15))
        capture("authorized-monthly-test-store-active", nativeCapture: true)
        print("AUTHORIZED_ZERO_CHARGE_MONTHLY official RevenueCat Test Store valid test purchase completed; production and StoreKit purchase not invoked")
    }

    /// Real CC Attribution paper is staged in Documents by the host, as an input
    /// file only. All research state below is created through native controls.
    func testRealSourceDocumentPickerQuoteRepairAndExport() throws {
        app.launch()
        tap(element("create-project"))
        fill(element("project-title"), "Kross 2013 source review")
        fill(element("research-question"), "What population does this study actually describe?")
        tap(element("confirm-create-project"))
        tap(element("capture-evidence"))
        tap(element("import-source-file"))
        XCTAssertTrue(app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].waitForExistence(timeout: 8))
        capture("real-source-picker-open")
        print("PICKER_ACCESSIBILITY " + app.debugDescription)
        chooseLocalFile(containing: "kross2013")
        XCTAssertTrue(element("quote-locator-result").waitForExistence(timeout: 15))
        fill(element("source-title"), "Kross et al. 2013", replacing: true)
        fill(element("source-origin"), "doi:10.1371/journal.pone.0069841; CC Attribution", replacing: true)
        fill(element("source-excerpt"), "Eighty-two people")
        fill(element("source-population"), "82 recruited young adults")
        dismissKeyboard()
        for _ in 0..<5 { app.swipeDown() }
        XCTAssertTrue(element("quote-locator-result").label.contains("Quote found"))
        capture("real-source-page-quote-match")
        tap(element("save-source"))
        tap(element("add-claim"))
        fill(element("claim-text"), "The study definitely represents all people.")
        turnOn(app.switches["Kross et al. 2013"])
        tap(element("save-claim"))
        tap(app.staticTexts["The study definitely represents all people."])
        capture("real-source-injected-overclaim")
        tap(element("repair-wording"))
        fill(element("repair-after"), "The study recruited 82 people.", replacing: true)
        fill(element("repair-reason"), "Restrict the injected QA claim to the quoted recruitment count.")
        tap(app.buttons["Preview repair"])
        capture("real-source-explicit-repair-preview")
        tap(element("accept-repair"))
        tap(element("start-standard-defense"))
        for question in ["basis", "change", "limit"] {
            fill(element("defense-answer-" + question), "The paper states Eighty-two people on PDF page 1. Recruitment does not establish generalizability.")
        }
        turnOn(app.switches["Kross et al. 2013"])
        fill(element("defense-limitation"), "Provisional QA annotation; no human research validation.")
        tap(element("save-defense"))
        capture("real-source-saved-defense")
        app.terminate(); app.launch()
        tap(app.staticTexts["Kross 2013 source review"])
        tap(element("prepare-pack"))
        tap(app.buttons["Open readable brief"])
        XCTAssertTrue(element("native-text-preview").waitForExistence(timeout: 10))
        XCTAssertTrue((element("native-text-preview").value as? String ?? "").contains("Research question"))
        capture("real-source-open-brief")
        dismissPreview()
        tap(app.buttons["Open reimportable archive"])
        XCTAssertTrue(element("native-text-preview").waitForExistence(timeout: 10))
        XCTAssertTrue((element("native-text-preview").value as? String ?? "").contains("events"))
        capture("real-source-open-archive")
        dismissPreview()
        XCTAssertTrue(app.buttons["Share reimportable archive"].exists)
    }

    func testPranavCausalReviewSourcePickerRepairAndExport() throws {
        app.launch()
        tap(element("create-project"))
        fill(element("project-title"), "Kross 2013 causal review")
        fill(element("research-question"), "What does the paper say is needed to establish causality?")
        tap(element("confirm-create-project"))
        tap(element("capture-evidence"))
        tap(element("import-source-file"))
        XCTAssertTrue(app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].waitForExistence(timeout: 8))
        capture("pranav-causal-picker-open")
        print("PICKER_ACCESSIBILITY " + app.debugDescription)
        chooseLocalFile(containing: "kross2013")
        XCTAssertTrue(element("quote-locator-result").waitForExistence(timeout: 15))
        tap(element("source-page"))
        tap(app.buttons["Page 5"])
        fill(element("source-title"), "Kross et al. 2013", replacing: true)
        fill(element("source-origin"), "doi:10.1371/journal.pone.0069841; CC Attribution", replacing: true)
        fill(element("source-excerpt"), "experiments that manipulate Facebook use in daily life are needed to corroborate these findings and establish definitive causal relations.")
        fill(element("source-population"), "82 recruited young adults")
        dismissKeyboard()
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Study design")).firstMatch)
        tap(app.buttons["Observational"])
        for _ in 0..<5 { app.swipeDown() }
        XCTAssertTrue(element("quote-locator-result").label.contains("Quote found"))
        capture("pranav-causal-page-quote-match")
        tap(element("save-source"))
        tap(element("add-claim"))
        fill(element("claim-text"), "A randomized experiment in this paper definitively established causality.")
        turnOn(app.switches["Kross et al. 2013"])
        tap(element("save-claim"))
        reveal(element("export-review-summary"))
        XCTAssertTrue(element("export-review-summary").label.contains("3 items"))
        capture("pranav-causal-unresolved-review-before-sharing")
        tap(element("prepare-pack"))
        tap(app.buttons["Open readable brief"])
        XCTAssertTrue(element("native-text-preview").waitForExistence(timeout: 10))
        let unresolved = element("native-text-preview").value as? String ?? ""
        XCTAssertTrue(unresolved.contains("Review before sharing"))
        XCTAssertTrue(unresolved.contains("This wording may imply causality"))
        XCTAssertTrue(unresolved.contains("This phrase asserts strong certainty."))
        XCTAssertTrue(unresolved.contains("7ba9667c23217f8f2571181b40884ce2e3d6342613425b6232ad56ebbcfeea8d"))
        capture("pranav-causal-unresolved-readable-brief")
        dismissPreview()
        for _ in 0..<8 { app.swipeDown() }
        tap(app.staticTexts["A randomized experiment in this paper definitively established causality."])
        capture("pranav-causal-injected-overclaim")
        tap(element("repair-wording"))
        fill(element("repair-after"), "The paper calls for experiments to establish causal relations.", replacing: true)
        fill(element("repair-reason"), "Scripted QA repair narrows the injected overclaim to the page 5 future-research statement; scientific meaning still needs human review.")
        tap(app.buttons["Preview repair"])
        capture("pranav-causal-explicit-repair-preview")
        tap(element("accept-repair"))
        tap(element("start-standard-defense"))
        for question in ["basis", "change", "limit"] {
            fill(element("defense-answer-" + question), "PDF page 5 calls for experiments to establish causal relations. This scripted QA answer records the limitation; no human validation has occurred.")
        }
        turnOn(app.switches["Kross et al. 2013"])
        fill(element("defense-limitation"), "Provisional QA annotation; no human research validation.")
        tap(element("save-defense"))
        capture("pranav-causal-saved-defense")
        app.terminate(); app.launch()
        tap(app.staticTexts["Kross 2013 causal review"])
        tap(element("prepare-pack"))
        tap(app.buttons["Open readable brief"])
        XCTAssertTrue(element("native-text-preview").waitForExistence(timeout: 10))
        XCTAssertTrue((element("native-text-preview").value as? String ?? "").contains("Research question"))
        capture("pranav-causal-open-brief")
        dismissPreview()
        tap(app.buttons["Open reimportable archive"])
        XCTAssertTrue(element("native-text-preview").waitForExistence(timeout: 10))
        XCTAssertTrue((element("native-text-preview").value as? String ?? "").contains("events"))
        capture("pranav-causal-open-archive")
        dismissPreview()
        XCTAssertTrue(app.buttons["Share reimportable archive"].exists)
    }

    func testPranavCausalArchiveReimportThroughPicker() throws {
        app.launch()
        tap(app.buttons["Import research archive"])
        chooseLocalFile(containing: "PranavCausalReimportQA")
        XCTAssertTrue(element("capture-evidence").waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["The paper calls for experiments to establish causal relations."].exists)
        tap(app.staticTexts["Kross et al. 2013"])
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "experiments that manipulate Facebook use")).firstMatch.waitForExistence(timeout: 5))
        capture("pranav-causal-reimported-source")
        back()
        tap(element("prepare-pack"))
        tap(app.buttons["Open readable brief"])
        XCTAssertTrue(element("native-text-preview").waitForExistence(timeout: 10))
        XCTAssertTrue((element("native-text-preview").value as? String ?? "").contains("Research question"))
        capture("pranav-causal-reimported-open-brief")
        dismissPreview()
        app.swipeUp()
        tap(app.buttons["Share reimportable archive"])
        let activity = element("ActivityListView")
        XCTAssertTrue(activity.waitForExistence(timeout: 8), "Native activity UI must actually present before this step is counted.")
        XCTAssertTrue(element("LP.CaptionBar.TopCaption").label.contains("Kross-2013-causal-review-event-archive"))
        capture("pranav-causal-native-share-sheet", nativeCapture: true)
        // ShareSheet remote accessibility wrapper has an empty hittable frame on iOS 27.
        // Drag the visible header area in this recorded iPhone test destination.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: activity)], timeout: 8), .completed)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Kross 2013 causal review"].waitForExistence(timeout: 10))
    }

    private func dismissPreview() {
        if app.buttons["Done"].waitForExistence(timeout: 3) { app.buttons["Done"].tap() }
        else { app.swipeDown() }
    }
    private func chooseLocalFile(containing name: String) {
        let file = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
        if file.waitForExistence(timeout: 3) && file.isHittable { file.tap(); return }
        for title in ["Browse", "Browse", "On My iPhone", "Research Pro"] {
            let target = app.buttons[title].exists ? app.buttons[title] : app.staticTexts[title]
            if target.waitForExistence(timeout: 2) && target.isHittable { target.tap() }
        }
        if !file.waitForExistence(timeout: 5) { capture("picker-file-missing"); print("PICKER_MISSING " + app.debugDescription) }
        XCTAssertTrue(file.exists && file.isHittable, "Staged local input must be selectable through the system picker.")
        file.tap()
    }

    func testNativeManuscriptProfileSwitchAndPreview() throws {
        app.launch()
        tap(element("try-sample"))
        tap(element("publication-workflow"))
        tap(element("edit-publication"))
        fill(element("manuscript-title"), "Formatting preservation fixture", replacing: true)
        fill(element("manuscript-abstract"), "A synthetic formatting fixture preserves 82 observations and literal notation. This is not a study or publication-ready paper.")
        tap(element("add-manuscript-section"))
        tap(app.buttons["Untitled section"])
        fill(element("manuscript-section-heading"), "Fixture content")
        tap(app.buttons["Add paragraph"])
        let paragraph = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Paragraph:")).firstMatch
        tap(paragraph)
        fill(element("manuscript-block-text"), "The canonical value is 82. Alpha and beta remain author content. This fixture measures content preservation, not scientific validity.")
        back(); back(); back()
        tap(element("save-publication"))
        XCTAssertTrue(element("publication-save-state").label.contains("revision 1"))
        tap(element("publication-preflight"))
        capture("publication-plos-honest-preflight")
        for name in ["PLOS ONE", "ICLR 2027", "PLOS ONE"] {
            if name == "ICLR 2027" || element("publication-profile").label.contains("ICLR") {
                for _ in 0..<8 { app.swipeDown() }
                tap(element("publication-profile"))
                let option = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
                tap(option)
            }
            tap(element("render-publication"))
            XCTAssertTrue(element("native-document-preview").waitForExistence(timeout: 15))
            Thread.sleep(forTimeInterval: 2)
            capture("publication-\(name)-native-pdf-preview")
            dismissPreview()
            for _ in 0..<8 { app.swipeDown() }
            XCTAssertTrue(element("publication-save-state").label.contains("revision 1"), "Style changes must not save a content revision")
        }
    }

    func testSourcePickerCancellationKeepsDraft() throws {
        app.launch(); tap(element("try-sample")); tap(element("capture-evidence"))
        fill(element("source-title"), "Uncommitted cancellation check")
        tap(element("import-source-file"))
        let pickerBar = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        let cancel = pickerBar.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: pickerBar)], timeout: 10), .completed)
        XCTAssertTrue(element("source-title").waitForExistence(timeout: 5))
        XCTAssertEqual(element("source-title").value as? String, "Uncommitted cancellation check")
        tap(app.buttons["Cancel"])
        XCTAssertFalse(app.staticTexts["Uncommitted cancellation check"].exists)
    }

    func testRealSourceArchiveReimportThroughPicker() throws {
        app.launch()
        tap(app.buttons["Import research archive"])
        chooseLocalFile(containing: "ReimportQA")
        XCTAssertTrue(element("capture-evidence").waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["The study recruited 82 people."].exists)
        tap(app.staticTexts["Kross et al. 2013"])
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Eighty-two people")).firstMatch.waitForExistence(timeout: 5))
        capture("real-source-reimported-source")
        back()
        tap(element("prepare-pack"))
        tap(app.buttons["Open readable brief"])
        XCTAssertTrue(element("native-text-preview").waitForExistence(timeout: 10))
        XCTAssertTrue((element("native-text-preview").value as? String ?? "").contains("Research question"))
        capture("real-source-reimported-open-brief")
        dismissPreview()
        app.swipeUp()
        tap(app.buttons["Share reimportable archive"])
        let activity = element("ActivityListView")
        XCTAssertTrue(activity.waitForExistence(timeout: 8), "Native activity UI must actually present before this step is counted.")
        XCTAssertTrue(element("LP.CaptionBar.TopCaption").label.contains("Kross-2013-source-review-event-archive"))
        capture("real-source-native-share-sheet", nativeCapture: true)
        // ShareSheet remote accessibility wrapper has an empty hittable frame on iOS 27.
        // Drag the visible header area in this recorded iPhone test destination.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: activity)], timeout: 8), .completed)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Kross 2013 source review"].waitForExistence(timeout: 10))
    }

    func testOptInTestStoreCancellationAndProviderFailure() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RESEARCH_PRO_ZERO_CHARGE_TEST_PURCHASE_AUTHORIZED"] == "YES", "Explicit zero-charge Test Store authorization required.")
        app.launch(); tap(app.buttons["Research Pro Plus"])
        let environment = element("subscriptionEnvironment")
        XCTAssertTrue(environment.waitForExistence(timeout: 15))
        XCTAssertTrue(environment.label.contains("RevenueCat Test Store") && environment.label.contains("no real charge"))
        let plans = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "Explore Research Pro Plus", "View plan options")).firstMatch
        reveal(plans)
        app.swipeUp() // Keep the plans row fully inside the sheet, above its rounded bottom edge.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND enabled == true"), object: plans)
        let readyResult = XCTWaiter.wait(for: [ready], timeout: 40)
        if readyResult != .completed { capture("provider-plans-unavailable"); print("UI_DIAGNOSTIC \(app.debugDescription)") }
        XCTAssertEqual(readyResult, .completed)
        tap(plans); tap(element("native-plan-$rc_monthly"))
        for action in ["Cancel", "Test failed purchase"] {
            tap(element("confirm-native-purchase"))
            let modal = app.alerts["Test Store Purchase"]
            XCTAssertTrue(modal.waitForExistence(timeout: 15))
            XCTAssertTrue(modal.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "This is a test purchase")).firstMatch.exists)
            capture("provider-official-modal-" + action)
            XCTAssertTrue(modal.buttons[action].exists, "Actual SDK action must match; no fallback purchase.")
            modal.buttons[action].tap()
            XCTAssertTrue(element("confirm-native-purchase").waitForExistence(timeout: 15))
            capture("provider-after-" + action)
        }
        tap(app.buttons["Close Plus plans"])
        XCTAssertFalse(app.staticTexts["Research Pro Plus — Test Store"].exists)
    }

    func testOptInNaturalTestStoreExpiryRetainsSavedResearch() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RESEARCH_PRO_PROVIDER_LIFECYCLE_AUTHORIZED"] == "YES", "Explicit provider lifecycle authorization required.")
        XCTAssertNotNil(ProcessInfo.processInfo.environment["RESEARCH_PRO_UI_FIXED_SESSION"], "Must reuse the exact saved premium research namespace.")
        app.launch(); tap(app.buttons["Research Pro Plus"])
        XCTAssertTrue(element("subscriptionEnvironment").waitForExistence(timeout: 10))
        XCTAssertTrue(element("subscriptionEnvironment").label.contains("RevenueCat Test Store"))
        tap(app.buttons["Refresh status"])
        for _ in 0..<5 { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["Free"].waitForExistence(timeout: 30), "Natural provider expiry must be observed; never alter local entitlement/cache.")
        capture("provider-natural-expiry-free")
        app.terminate(); app.launch()
        tap(app.staticTexts["Provider verification B"])
        // The free-project notice makes the claim row initially intersect the bottom safe area.
        app.swipeUp()
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "This note documents the verification example.")).firstMatch)
        XCTAssertTrue(app.navigationBars["Review & defend"].waitForExistence(timeout: 5))
        tap(app.staticTexts["Advanced defense"])
        XCTAssertTrue(element("defense-answer-basis").waitForExistence(timeout: 5))
        XCTAssertEqual(element("defense-answer-basis").value as? String, "The exact note describes this example.")
        capture("provider-expired-history-retained")
        back(); back()
        tap(element("prepare-pack"))
        tap(app.buttons["Open readable brief"])
        XCTAssertTrue(element("native-text-preview").waitForExistence(timeout: 10))
        XCTAssertTrue((element("native-text-preview").value as? String ?? "").contains("Research question"))
        capture("provider-expired-export-open")
        dismissPreview()
        app.terminate(); app.launch()
        tap(element("create-project"))
        XCTAssertTrue(element("subscriptionEnvironment").waitForExistence(timeout: 15), "Additional new project must be gated after fresh provider expiry.")
        XCTAssertFalse(element("confirm-create-project").exists)
        capture("provider-expired-new-project-gated")
        print("PROVIDER_NATURAL_EXPIRY retained saved advanced answers, opened readable export, new additional project gated by actual refreshed CustomerInfo")
    }

}
