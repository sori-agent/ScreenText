import AppKit
import XCTest
@testable import TRexCore

/// Opt-in proof of the configured local model through the real clipboard pipeline.
@MainActor
final class LocalOCRIntegrationTests: XCTestCase {
    func testProvidedImageReachesClipboardVerbatim() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let imagePath = environment["SCREENTEXT_TEST_IMAGE"],
              let expectedPath = environment["SCREENTEXT_TEST_EXPECTED"] else {
            throw XCTSkip("Provide private image and expected-text paths to run local-model integration.")
        }
        let preferences = Preferences.shared
        XCTAssertTrue(preferences.llmEnabled && preferences.llmEnableOCR)
        XCTAssertEqual(preferences.llmOCRProvider, "Custom")
        XCTAssertEqual(preferences.llmOCRCustomEndpoint, "http://127.0.0.1:18871/v1")
        XCTAssertFalse(preferences.captureHistoryEnabled)
        XCTAssertFalse(preferences.llmFallbackToBuiltIn)
        XCTAssertFalse(preferences.llmEnablePostProcessing)
        XCTAssertFalse(preferences.ignoreLineBreaks)
        XCTAssertFalse(preferences.tableDetectionEnabled)
        TRex.shared.initializeLLM()
        let expected = try String(contentsOfFile: expectedPath, encoding: .utf8)

        let success = await TRex.shared.capture(.captureFromFile, imagePath: imagePath)

        XCTAssertTrue(success)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), expected)
    }
}
