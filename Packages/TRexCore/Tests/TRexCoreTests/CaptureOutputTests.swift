import XCTest
@testable import TRexCore

@MainActor
final class CaptureOutputTests: XCTestCase {
    func testCLIOutputIsEmittedEvenWhenClipboardWriteFails() {
        var printed = [String]()

        let wroteToClipboard = TRex.emitCaptureOutput(
            "recognized text",
            isCLI: true,
            writeToClipboard: { _ in false },
            printLine: { printed.append($0) }
        )

        XCTAssertFalse(wroteToClipboard)
        XCTAssertEqual(printed, ["recognized text"])
    }

    func testCLIOutputIsEmittedWhenClipboardWriteSucceeds() {
        var printed = [String]()
        var readySoundCount = 0

        let wroteToClipboard = TRex.emitCaptureOutput(
            "recognized text",
            isCLI: true,
            writeToClipboard: { _ in true },
            printLine: { printed.append($0) },
            playReadySound: { readySoundCount += 1 }
        )

        XCTAssertTrue(wroteToClipboard)
        XCTAssertEqual(printed, ["recognized text"])
        XCTAssertEqual(readySoundCount, 0)
    }

    func testGUIInvocationDoesNotPrintToStandardOutput() {
        var printed = [String]()

        _ = TRex.emitCaptureOutput(
            "recognized text",
            isCLI: false,
            writeToClipboard: { _ in true },
            printLine: { printed.append($0) }
        )

        XCTAssertTrue(printed.isEmpty)
    }

    func testGUIReadySoundRunsAfterSuccessfulClipboardWrite() {
        var events = [String]()

        let wroteToClipboard = TRex.emitCaptureOutput(
            "recognized text",
            isCLI: false,
            writeToClipboard: { _ in
                events.append("clipboard")
                return true
            },
            printLine: { _ in events.append("stdout") },
            playReadySound: { events.append("ready sound") }
        )

        XCTAssertTrue(wroteToClipboard)
        XCTAssertEqual(events, ["clipboard", "ready sound"])
    }

    func testFailedClipboardWriteDoesNotPlayReadySound() {
        var readySoundCount = 0

        let wroteToClipboard = TRex.emitCaptureOutput(
            "recognized text",
            isCLI: false,
            writeToClipboard: { _ in false },
            printLine: { _ in },
            playReadySound: { readySoundCount += 1 }
        )

        XCTAssertFalse(wroteToClipboard)
        XCTAssertEqual(readySoundCount, 0)
    }
}
