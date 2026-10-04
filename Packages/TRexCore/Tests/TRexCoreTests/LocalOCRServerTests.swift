import Darwin
import Foundation
import XCTest
@testable import TRexCore

/// Exercise server ownership against a real child process without loading a model.
@MainActor
final class LocalOCRServerTests: XCTestCase {
    func testStoppingTheOwnerEndsItsChildAndRemovesThePIDFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let runtime = root.appendingPathComponent(".venv/bin/python")
        let script = root.appendingPathComponent("Tools/local_ocr/server.py")
        for directory in [runtime.deletingLastPathComponent(), script.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "#!/bin/sh\nexec /bin/sleep 300\n".write(to: runtime, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
        try "".write(to: script, atomically: true, encoding: .utf8)
        let server = LocalOCRServer()
        defer {
            server.stop()
            try? FileManager.default.removeItem(at: root)
        }

        let pid = try server.start(projectDirectory: root)
        XCTAssertEqual(kill(pid, 0), 0)
        XCTAssertEqual(try server.start(projectDirectory: root), pid, "Starting twice must not leak another server.")
        let pidFile = root.appendingPathComponent(".local/server.pid")
        XCTAssertEqual(try String(contentsOf: pidFile, encoding: .utf8), String(pid))

        server.stop()

        XCTAssertEqual(kill(pid, 0), -1, "The model process must be gone when its owner stops.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: pidFile.path))
        server.stop() // Repeated termination must remain harmless.
    }
}
