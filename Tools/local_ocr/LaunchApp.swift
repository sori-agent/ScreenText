import AppKit
import Foundation

// LaunchServices gives ScreenText its own permission identity. Executing its
// binary directly makes macOS attribute screen capture to the invoking app.
guard CommandLine.arguments.count == 2,
      let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !key.isEmpty else {
    exit(1)
}
let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = false
configuration.environment = ["OPENROUTER_API_KEY": key]
NSWorkspace.shared.openApplication(
    at: URL(fileURLWithPath: CommandLine.arguments[1]),
    configuration: configuration
) { application, error in
    exit(application != nil && error == nil ? 0 : 1)
}
RunLoop.main.run()
