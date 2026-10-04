import Darwin
import Foundation

/// Own the offline model process for exactly as long as the menu bar app runs.
@MainActor
public final class LocalOCRServer {
    public static let shared = LocalOCRServer()
    private var process: Process?
    private var pidFile: URL?

    public init() {}

    /// Launch this installation's runtime once; keep model weights offline.
    @discardableResult
    public func start(projectDirectory root: URL) throws -> Int32 {
        if let process, process.isRunning { return process.processIdentifier }
        let directory = root.appendingPathComponent(".local", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logURL = directory.appendingPathComponent("server.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        try log.truncate(atOffset: 0)

        let child = Process()
        child.executableURL = root.appendingPathComponent(".venv/bin/python")
        child.arguments = [root.appendingPathComponent("Tools/local_ocr/server.py").path,
                           "--model", "PaddlePaddle/PaddleOCR-VL-1.6",
                           "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
        child.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"] = "1"
        environment["HF_HOME"] = root.appendingPathComponent(".local/huggingface").path
        child.environment = environment
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = log
        child.standardError = log
        try child.run()
        process = child
        pidFile = directory.appendingPathComponent("server.pid")
        do {
            try String(child.processIdentifier).write(to: pidFile!, atomically: true, encoding: .utf8)
        } catch {
            stop()
            throw error
        }
        return child.processIdentifier
    }

    /// A capture made during startup waits for this app's model to be ready.
    public func waitUntilReady(for endpoint: String?) async throws {
        guard let endpoint, let url = URL(string: endpoint), url.scheme == "http",
              ["127.0.0.1", "localhost"].contains(url.host ?? ""), url.port == 18871,
              let child = process else { return }
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        let health = URL(string: "http://127.0.0.1:18871/health")!
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            guard child.isRunning else { throw StartupError.serverExited }
            let request = URLRequest(url: health, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1)
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let status = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               status["ready"] as? Bool == true,
               (status["pid"] as? NSNumber)?.int32Value == child.processIdentifier {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw StartupError.timedOut
    }

    /// OCR holds only in-memory work; end it immediately, even during inference.
    public func stop() {
        guard let child = process else { return }
        if child.isRunning {
            kill(child.processIdentifier, SIGKILL)
            child.waitUntilExit()
        }
        if let pidFile,
           (try? String(contentsOf: pidFile, encoding: .utf8)) == String(child.processIdentifier) {
            try? FileManager.default.removeItem(at: pidFile)
        }
        process = nil
        pidFile = nil
    }

    private enum StartupError: LocalizedError {
        case serverExited, timedOut
        var errorDescription: String? {
            switch self {
            case .serverExited: "The local OCR server stopped. Reopen ScreenText to restart it."
            case .timedOut: "The local OCR model did not finish loading. Reopen ScreenText to try again."
            }
        }
    }
}
