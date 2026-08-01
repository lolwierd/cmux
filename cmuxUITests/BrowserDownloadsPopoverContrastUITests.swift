import CoreGraphics
import Foundation
import ImageIO
import XCTest

final class BrowserDownloadsPopoverContrastUITests: XCTestCase {
    private var app: XCUIApplication?
    private var isolatedHome: URL?
    private var setupPath = ""

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        setupPath = "/tmp/cmux-ui-test-downloads-popover-\(UUID().uuidString).json"
        try? FileManager.default.removeItem(atPath: setupPath)
    }

    override func tearDown() {
        app?.terminate()
        if let isolatedHome {
            try? FileManager.default.removeItem(at: isolatedHome)
        }
        try? FileManager.default.removeItem(atPath: setupPath)
        super.tearDown()
    }

    func testDownloadsPopoverKeepsLightChromeReadableWhenAppKitAppearanceIsDark() throws {
        let isolatedHome = try makeIsolatedHomeWithLightTerminalTheme()
        self.isolatedHome = isolatedHome

        let app = XCUIApplication.cmuxTestApplication()
        self.app = app
        app.launchArguments += [
            "-appearanceMode", "dark",
            "-browserThemeMode", "light",
            "-browserAskWhereToSaveDownloads", "false",
        ]
        app.launchEnvironment["HOME"] = isolatedHome.path
        app.launchEnvironment["CFFIXED_USER_HOME"] = isolatedHome.path
        app.launchEnvironment["XDG_CONFIG_HOME"] =
            isolatedHome.appendingPathComponent(".config", isDirectory: true).path
        app.launchEnvironment["CMUX_UI_TEST_MODE"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_SETUP"] = "1"
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_PATH"] = setupPath
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_BROWSER_URL"] = makeDownloadPageDataURL()
        app.launchEnvironment["CMUX_UI_TEST_GOTO_SPLIT_USE_GHOSTTY_CONFIG"] = "1"
        let launchOptions = XCTExpectedFailure.Options()
        launchOptions.isStrict = false
        XCTExpectFailure("App activation may fail on headless CI runners", options: launchOptions) {
            app.launch()
        }

        XCTAssertTrue(
            ensureForegroundAfterLaunch(app, timeout: 12),
            "Expected cmux to launch in the foreground"
        )
        XCTAssertTrue(
            waitForSetupData(timeout: 12) { $0["browserPageTitle"] == "downloads-popover-contrast" },
            "Expected the synthetic download page to finish loading. data=\(loadSetupData() ?? [:])"
        )

        let downloadLink = app.links["Download error.txt"].firstMatch
        XCTAssertTrue(downloadLink.waitForExistence(timeout: 8), "Expected the synthetic download link")
        downloadLink.click()

        let downloadsButton = app.descendants(matching: .any)
            .matching(identifier: "BrowserDownloadsButton")
            .firstMatch
        XCTAssertTrue(
            downloadsButton.waitForExistence(timeout: 15),
            "Expected the downloads toolbar button after starting a download"
        )
        downloadsButton.click()

        let popover = app.descendants(matching: .any)
            .matching(identifier: "BrowserDownloadsPopover")
            .firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5), "Expected the Downloads popover")

        let title = app.descendants(matching: .any)
            .matching(identifier: "BrowserDownloadsPopoverTitle")
            .firstMatch
        let filename = app.descendants(matching: .any)
            .matching(identifier: "BrowserDownloadFilename")
            .firstMatch
        let openButton = app.descendants(matching: .any)
            .matching(identifier: "BrowserDownloadOpenButton")
            .firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "Expected the Downloads heading")
        XCTAssertTrue(filename.waitForExistence(timeout: 15), "Expected the completed download row")
        XCTAssertTrue(openButton.waitForExistence(timeout: 15), "Expected the completed download action")

        try assertReadableLightChrome(behind: title, attachmentName: "downloads-popover-title")
        try assertReadableLightChrome(behind: filename, attachmentName: "downloads-popover-filename")
    }

    private func makeIsolatedHomeWithLightTerminalTheme() throws -> URL {
        let fileManager = FileManager.default
        let home = fileManager.temporaryDirectory.appendingPathComponent(
            "cmux-ui-test-downloads-popover-home-\(UUID().uuidString)",
            isDirectory: true
        )
        let ghosttyDirectory = home
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("com.mitchellh.ghostty", isDirectory: true)
        try fileManager.createDirectory(at: ghosttyDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: home.appendingPathComponent("Downloads", isDirectory: true),
            withIntermediateDirectories: true
        )

        let config = """
        # Force browser chrome to resolve light while AppKit remains dark.
        working-directory = \(home.path)
        background = #f5f5f5
        foreground = #111111
        background-opacity = 1

        """
        try config.write(
            to: ghosttyDirectory.appendingPathComponent("config.ghostty", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )
        return home
    }

    private func makeDownloadPageDataURL() -> String {
        let payload = Data(repeating: 0x41, count: 5_400).base64EncodedString()
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>downloads-popover-contrast</title>
          <style>
            html, body {
              margin: 0;
              min-height: 100%;
              background: #151515;
              color: #f4f4f4;
              font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            }
            main { padding: 96px 32px; }
            a { color: #8ab4f8; font-size: 18px; }
          </style>
        </head>
        <body>
          <main>
            <a
              href="data:text/plain;base64,\(payload)"
              download="error.txt"
              aria-label="Download error.txt"
            >Download error.txt</a>
          </main>
        </body>
        </html>
        """
        return "data:text/html;base64,\(Data(html.utf8).base64EncodedString())"
    }

    private func ensureForegroundAfterLaunch(
        _ app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        if app.wait(for: .runningForeground, timeout: timeout) {
            return true
        }
        guard app.state == .runningBackground else { return false }
        app.activate()
        return app.wait(for: .runningForeground, timeout: 6)
    }

    private func waitForSetupData(
        timeout: TimeInterval,
        predicate: @escaping ([String: String]) -> Bool
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                guard let data = self.loadSetupData() else { return false }
                return predicate(data)
            },
            object: nil
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func loadSetupData() -> [String: String]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: setupPath)) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
    }

    private func assertReadableLightChrome(
        behind element: XCUIElement,
        attachmentName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let screenshot = element.screenshot()
        let attachment = XCTAttachment(
            data: screenshot.pngRepresentation,
            uniformTypeIdentifier: "public.png"
        )
        attachment.name = attachmentName
        attachment.lifetime = .keepAlways
        add(attachment)

        let luminances = try renderedLuminances(fromPNG: screenshot.pngRepresentation).sorted()
        XCTAssertGreaterThan(luminances.count, 100, "Expected rendered pixels", file: file, line: line)
        guard luminances.count > 100 else { return }

        let foreground = percentile(0.02, in: luminances)
        let background = percentile(0.85, in: luminances)
        let contrastRatio = (background + 0.05) / (foreground + 0.05)

        XCTAssertGreaterThan(
            background,
            0.65,
            "Expected the light browser-chrome backdrop behind \(attachmentName), background=\(background)",
            file: file,
            line: line
        )
        XCTAssertLessThan(
            foreground,
            0.35,
            "Expected dark semantic foreground pixels in \(attachmentName), foreground=\(foreground)",
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            contrastRatio,
            4.5,
            "Expected readable foreground/backdrop contrast in \(attachmentName), ratio=\(contrastRatio)",
            file: file,
            line: line
        )
    }

    private func renderedLuminances(fromPNG pngData: Data) throws -> [Double] {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw XCTSkip("Could not decode popover screenshot PNG")
        }

        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var bytes = [UInt8](repeating: 0, count: height * bytesPerRow)
        let bitmapInfo =
            CGBitmapInfo.byteOrder32Big.rawValue |
            CGImageAlphaInfo.premultipliedLast.rawValue
        let didDraw = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                      data: baseAddress,
                      width: width,
                      height: height,
                      bitsPerComponent: 8,
                      bytesPerRow: bytesPerRow,
                      space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: bitmapInfo
                  ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else {
            throw XCTSkip("Could not render popover screenshot into an RGBA buffer")
        }

        return stride(from: 0, to: bytes.count, by: bytesPerPixel).compactMap { offset in
            guard bytes[offset + 3] > 242 else { return nil }
            let red = linearizedSRGB(Double(bytes[offset]) / 255)
            let green = linearizedSRGB(Double(bytes[offset + 1]) / 255)
            let blue = linearizedSRGB(Double(bytes[offset + 2]) / 255)
            return 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
    }

    private func linearizedSRGB(_ component: Double) -> Double {
        component <= 0.04045
            ? component / 12.92
            : pow((component + 0.055) / 1.055, 2.4)
    }

    private func percentile(_ fraction: Double, in sortedValues: [Double]) -> Double {
        let index = Int((Double(sortedValues.count - 1) * fraction).rounded())
        return sortedValues[index]
    }
}
