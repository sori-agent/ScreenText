import Cocoa
import CoreGraphics
import OSLog
import ScreenCaptureKit

/// Shows an adjustable selection over a frozen display snapshot. The user moves or resizes
/// the rectangle, then confirms; only its cropped pixels reach OCR.
@MainActor
public enum FrozenScreenSelectionOverlay {
    /// Returns the cropped pixel image of the user's selection, or nil if cancelled / failed.
    public static func selectRegion() async -> NSImage? {
        await SelectionCoordinator().run()
    }
}

// MARK: - Coordinator

@MainActor
private final class SelectionCoordinator {
    private var windows: [SelectionWindow] = []
    private var continuation: CheckedContinuation<NSImage?, Never>?
    private var keyMonitor: Any?
    private var didResume = false
    private var previouslyActiveApp: NSRunningApplication?
    private var savedActivationPolicy: NSApplication.ActivationPolicy = .accessory

    func run() async -> NSImage? {
        FrozenLogger.shared.info("🧊 FrozenScreenSelectionOverlay.run() invoked")
        previouslyActiveApp = NSWorkspace.shared.frontmostApplication

        // Capture every display BEFORE we put up any UI — if we did it after, our overlays
        // would appear in the screenshot.
        let captures = await captureAllDisplays()
        FrozenLogger.shared.info("🧊 Captured \(captures.count, privacy: .public) display(s)")
        if captures.isEmpty {
            FrozenLogger.shared.error("🧊 No displays could be captured for freeze overlay — likely Screen Recording permission missing")
            return nil
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<NSImage?, Never>) in
            self.continuation = cont
            self.start(with: captures)
        }
    }

    private func start(with captures: [(NSScreen, CGImage)]) {
        for (screen, cgImage) in captures {
            FrozenLogger.shared.info("🧊 Building window for screen \(screen.frame.debugDescription, privacy: .public) image=\(cgImage.width, privacy: .public)x\(cgImage.height, privacy: .public)")
            let window = SelectionWindow(screen: screen, screenshot: cgImage, coordinator: self)
            windows.append(window)
        }

        if windows.isEmpty {
            FrozenLogger.shared.error("🧊 No windows built")
            finish(with: nil)
            return
        }

        // LSUIElement apps need accessory policy bumped to .regular momentarily so windows
        // can become key and receive keyboard events; we restore on finish().
        savedActivationPolicy = NSApp.activationPolicy()
        if savedActivationPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
        FrozenLogger.shared.info("🧊 Activated app, ordering \(self.windows.count, privacy: .public) window(s)")

        // Pick the window under the mouse to become key so its first responder gets keyDown.
        let mouseLoc = NSEvent.mouseLocation
        let preferred = windows.first(where: { $0.screen?.frame.contains(mouseLoc) == true }) ?? windows.first
        for window in windows {
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
        preferred?.makeKeyAndOrderFront(nil)
        preferred?.beginSelection()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // ESC
                self.finish(with: nil)
                return nil
            }
            return event
        }
    }

    /// Only one display owns the active rectangle at a time.
    func activateSelection(in view: SelectionView) {
        for window in windows { window.clearSelection(except: view) }
    }

    func finish(with image: NSImage?) {
        guard !didResume else { return }
        didResume = true

        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }

        for window in windows {
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()

        // Restore activation policy (accessory for menu-bar app) and focus.
        if NSApp.activationPolicy() != savedActivationPolicy {
            NSApp.setActivationPolicy(savedActivationPolicy)
        }
        if let previouslyActiveApp {
            previouslyActiveApp.activate()
        }

        continuation?.resume(returning: image)
        continuation = nil
    }

    /// Use ScreenCaptureKit's one-shot screenshot API (macOS 14.0+) to grab a still of each
    /// connected display and pair it with its matching NSScreen.
    private func captureAllDisplays() async -> [(NSScreen, CGImage)] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            var results: [(NSScreen, CGImage)] = []
            for display in content.displays {
                guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else {
                    continue
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width * Int(screen.backingScaleFactor)
                config.height = display.height * Int(screen.backingScaleFactor)
                config.showsCursor = false
                config.capturesAudio = false
                do {
                    let image = try await SCScreenshotManager.captureImage(
                        contentFilter: filter,
                        configuration: config
                    )
                    results.append((screen, image))
                } catch {
                    FrozenLogger.shared.error("Screenshot failed for display \(display.displayID): \(error.localizedDescription, privacy: .public)")
                }
            }
            return results
        } catch {
            FrozenLogger.shared.error("SCShareableContent failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

// MARK: - Logger holder

private enum FrozenLogger {
    static let shared = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.ameba.TRex",
        category: "FrozenSelection"
    )
}

// MARK: - NSScreen helper

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

// MARK: - Window

@MainActor
private final class SelectionWindow: NSWindow {
    private let selectionView: SelectionView

    init(screen: NSScreen, screenshot: CGImage, coordinator: SelectionCoordinator) {
        self.selectionView = SelectionView(screenshot: screenshot, coordinator: coordinator)

        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.isOpaque = true
        self.backgroundColor = .black
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        self.ignoresMouseEvents = false
        self.isReleasedWhenClosed = false
        self.acceptsMouseMovedEvents = true
        self.setFrame(screen.frame, display: true)
        self.contentView = selectionView
        self.initialFirstResponder = selectionView
        self.title = "Select Text"
    }

    func beginSelection() {
        selectionView.selectDefaultRegion()
    }

    func clearSelection(except activeView: SelectionView) {
        if selectionView !== activeView { selectionView.clearSelection() }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Selection view

@MainActor
private final class SelectionView: NSView {
    private enum Drag {
        case move(CGRect, CGPoint)
        case resize(CGRect, SelectionHandle, CGPoint)
    }

    private let screenshot: CGImage
    private weak var coordinator: SelectionCoordinator?
    private var selectionRect: CGRect?
    private var drag: Drag?
    private let controls = NSStackView()

    init(screenshot: CGImage, coordinator: SelectionCoordinator) {
        self.screenshot = screenshot
        self.coordinator = coordinator
        super.init(frame: .zero)
        wantsLayer = true

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelSelection))
        cancel.bezelStyle = .rounded
        let copy = NSButton(title: "Copy Text", target: self, action: #selector(finishSelection))
        copy.bezelStyle = .rounded
        copy.keyEquivalent = "\r"
        copy.toolTip = "Copy text from the selected rectangle (Return)"
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        controls.addArrangedSubview(cancel)
        controls.addArrangedSubview(copy)
        controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        controls.layer?.cornerRadius = 8
        controls.isHidden = true
        addSubview(controls)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Start with a small selection; the user can move and resize it before copying.
    func selectDefaultRegion(near point: CGPoint? = nil) {
        let size = CGSize(width: min(600, bounds.width * 0.45), height: min(300, bounds.height * 0.3))
        let center = point ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let rect = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                          width: size.width, height: size.height)
        selectionRect = SelectionGeometry.moved(rect, by: .zero, within: bounds)
        updateSelectionUI()
    }

    func clearSelection() {
        selectionRect = nil
        drag = nil
        updateSelectionUI()
    }

    override func layout() {
        super.layout()
        positionControls()
    }

    /// Keep native buttons next to the selection, inside the visible display.
    private func positionControls() {
        guard let rect = selectionRect else { return }
        let size = controls.fittingSize
        let x = min(max(rect.maxX - size.width, bounds.minX + 8), bounds.maxX - size.width - 8)
        let below = rect.minY - size.height - 12
        let y = below >= bounds.minY + 8 ? below : min(rect.maxY + 12, bounds.maxY - size.height - 8)
        controls.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func updateSelectionUI() {
        controls.isHidden = selectionRect == nil || drag != nil
        positionControls()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
        guard let rect = selectionRect else { return }
        addCursorRect(rect, cursor: .openHand)
        for handle in SelectionHandle.allCases {
            let cursor: NSCursor
            switch handle {
            case .left, .right: cursor = .resizeLeftRight
            case .top, .bottom: cursor = .resizeUpDown
            default: cursor = .crosshair
            }
            addCursorRect(hitRect(for: handle, in: rect), cursor: cursor)
        }
        if !controls.isHidden { addCursorRect(controls.frame, cursor: .arrow) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(screenshot, in: bounds)
        let outside = CGMutablePath()
        outside.addRect(bounds)
        if let rect = selectionRect { outside.addRect(rect) }
        context.addPath(outside)
        context.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        context.fillPath(using: .evenOdd)
        guard let rect = selectionRect else { return }
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)
        context.stroke(rect)
        for handle in SelectionHandle.allCases {
            let point = SelectionGeometry.position(of: handle, in: rect)
            let knob = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: knob)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
            context.setLineWidth(1)
            context.strokeEllipse(in: knob)
        }
    }

    private func hitRect(for handle: SelectionHandle, in rect: CGRect) -> CGRect {
        let point = SelectionGeometry.position(of: handle, in: rect)
        return CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
    }

    private func boundedPoint(from event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                       y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKeyAndOrderFront(nil)
        let point = boundedPoint(from: event)
        if selectionRect == nil {
            coordinator?.activateSelection(in: self)
            selectDefaultRegion(near: point)
        }
        guard let rect = selectionRect else { return }
        if let handle = SelectionHandle.allCases.first(where: { hitRect(for: $0, in: rect).contains(point) }) {
            drag = .resize(rect, handle, point)
        } else if rect.contains(point) {
            drag = .move(rect, point)
            NSCursor.closedHand.set()
        }
        updateSelectionUI()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        let point = boundedPoint(from: event)
        switch drag {
        case let .move(rect, origin):
            selectionRect = SelectionGeometry.moved(rect, by: CGSize(width: point.x - origin.x,
                height: point.y - origin.y), within: bounds)
        case let .resize(rect, handle, origin):
            let handleOrigin = SelectionGeometry.position(of: handle, in: rect)
            let target = CGPoint(x: handleOrigin.x + point.x - origin.x,
                                 y: handleOrigin.y + point.y - origin.y)
            selectionRect = SelectionGeometry.resized(rect, handle: handle, to: target, within: bounds)
        }
        updateSelectionUI()
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        drag = nil
        updateSelectionUI()
    }

    /// OCR receives only the confirmed rectangle, cropped from the in-memory snapshot.
    @objc private func finishSelection() {
        guard let rect = selectionRect else { return }
        let crop = SelectionGeometry.pixelCrop(for: rect, viewBounds: bounds,
            imageSize: CGSize(width: screenshot.width, height: screenshot.height))
        guard !crop.isNull, let cropped = screenshot.cropping(to: crop) else {
            coordinator?.finish(with: nil)
            return
        }
        coordinator?.finish(with: NSImage(cgImage: cropped,
            size: NSSize(width: cropped.width, height: cropped.height)))
    }

    @objc private func cancelSelection() {
        coordinator?.finish(with: nil)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: cancelSelection()
        case 36, 76: finishSelection()
        default: super.keyDown(with: event)
        }
    }
}
