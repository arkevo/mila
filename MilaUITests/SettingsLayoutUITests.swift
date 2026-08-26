import XCTest

/// Regression guard for the Settings overflow on macOS 26 (beads mila-ju8).
///
/// Since #194 the Settings window is a `NavigationSplitView`. On macOS 26 the
/// detail column proposes an unbounded height; a section rooted in a bare
/// `VStack` then grows to thousands of points and is centred on the window,
/// so its heading — and the whole sidebar with it — sit far outside the
/// visible frame and the window looks blank. Measured before the fix: the
/// General split view was 900×6115 pt inside a 900×472 pt window.
///
/// The universal detector is the sidebar: it is stretched together with the
/// detail, so after selecting any section the sidebar's own "General" label
/// must still lie inside the window. Sections with an unambiguous heading get
/// a second assertion on that heading.
final class SettingsLayoutUITests: XCTestCase {

    private struct Section {
        /// `SettingsTab.accessibilityID` — the sidebar row's identifier.
        let id: String
        /// Window title once the section is selected (`navigationTitle`).
        let title: String
        /// A heading whose text appears nowhere else in the window (nil when
        /// the section's heading equals its title, which the title bar and
        /// sidebar also show).
        let heading: String?
    }

    private static let sections: [Section] = [
        .init(id: "settings.section.general", title: "General", heading: "Dictation hotkeys"),
        .init(id: "settings.section.audio", title: "Audio", heading: "Input source"),
        .init(id: "settings.section.models", title: "Models", heading: "Transcription backend"),
        .init(id: "settings.section.aiProvider", title: "AI Provider", heading: nil),
        .init(id: "settings.section.aiFeatures", title: "AI Features", heading: nil),
        .init(id: "settings.section.speakers", title: "Speakers", heading: "Speaker diarization"),
        .init(id: "settings.section.meetings", title: "Meetings", heading: nil),
        .init(id: "settings.section.voiceMemos", title: "Voice Memos", heading: nil),
        .init(id: "settings.section.storage", title: "Storage", heading: "Recordings location"),
    ]

    override func setUp() {
        super.setUp()
        // One run reports every broken section, not just the first.
        continueAfterFailure = true
    }

    func test_every_settings_section_lays_out_inside_the_window() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitests"]
        app.launch()

        // Open Settings through the app menu rather than a synthesised Cmd+,
        // which needs a key window to land on and silently does nothing
        // under XCUITest when there isn't one yet.
        let appMenu = app.menuBars.firstMatch.menuBarItems["Mila"]
        XCTAssertTrue(appMenu.waitForExistence(timeout: 10), "app menu missing")
        appMenu.click()
        let settingsItem = appMenu.menuItems
            .matching(NSPredicate(format: "title BEGINSWITH 'Settings'")).firstMatch
        XCTAssertTrue(settingsItem.waitForExistence(timeout: 5), "Settings… menu item missing")
        settingsItem.click()
        XCTAssertTrue(app.windows["General"].waitForExistence(timeout: 10),
                      "Settings should open on the General section; windows seen: "
                      + app.windows.allElementsBoundByIndex.map(\.title).description)

        for section in Self.sections {
            // The sidebar row carries a stable identifier. In the broken
            // layout the row sits thousands of points above the window, so
            // the click cannot land — a legitimate failure of this test.
            let row = app.windows.firstMatch.descendants(matching: .any)
                .matching(identifier: section.id).firstMatch
            if row.waitForExistence(timeout: 5), row.isHittable {
                row.click()
            } else {
                XCTFail("\(section.title): sidebar row \(section.id) missing or not hittable "
                        + "(frame \(row.exists ? "\(row.frame)" : "n/a"))")
            }

            let window = app.windows[section.title]
            guard window.waitForExistence(timeout: 5) else {
                XCTFail("\(section.title): window title did not change (selection failed)")
                continue
            }
            let frame = window.frame

            // Scoped to the outline so the window-title static text, which is
            // also "General" while that section is selected, cannot match.
            let sidebarLabel = window.outlines.firstMatch.staticTexts["General"].firstMatch
            assertInside(sidebarLabel, frame, "\(section.title): sidebar label 'General'")

            if let heading = section.heading {
                let el = window.staticTexts[heading].firstMatch
                assertInside(el, frame, "\(section.title): heading '\(heading)'")
            }
        }
    }

    private func assertInside(_ element: XCUIElement, _ window: CGRect, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("\(what) does not exist", file: file, line: line)
            return
        }
        let f = element.frame
        XCTAssertGreaterThan(f.width, 0, "\(what) has zero width (frame \(f))", file: file, line: line)
        XCTAssertGreaterThan(f.height, 0, "\(what) has zero height (frame \(f))", file: file, line: line)
        XCTAssertTrue(window.contains(f),
                      "\(what) lies outside the window: element \(f) vs window \(window)",
                      file: file, line: line)
    }
}
