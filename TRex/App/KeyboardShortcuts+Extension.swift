import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureScreen = Self("captureScreen", default: .init(.two, modifiers: [.command, .shift]))
    static let captureScreenAndTriggerAutomation = Self("captureScreenAndTriggerAutomation")
    static let captureClipboard = Self("captureClipboard")
    static let captureClipboardAndTriggerAutomation = Self("captureClipboardAndTriggerAutomation")
    static let captureMultiRegion = Self("captureMultiRegion")
    static let captureMultiRegionAndTriggerAutomation = Self("captureMultiRegionAndTriggerAutomation")
}
