import CoreGraphics

/// The eight resize handles around a selection in Cocoa view coordinates.
enum SelectionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

/// Pure geometry shared by dragging, resizing, and the final pixel crop.
enum SelectionGeometry {
    /// Locate a handle without depending on the overlay's drawing or hit testing.
    static func position(of handle: SelectionHandle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .top: CGPoint(x: rect.midX, y: rect.maxY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.maxY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    /// Keep the selection inside the view, shrinking only if the view became smaller.
    static func moved(_ rect: CGRect, by delta: CGSize, within bounds: CGRect) -> CGRect {
        let rect = rect.standardized
        let bounds = bounds.standardized
        guard !rect.isNull, !bounds.isEmpty else { return .null }
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        return CGRect(x: clamped(rect.minX + delta.width, between: bounds.minX, and: bounds.maxX - width),
                      y: clamped(rect.minY + delta.height, between: bounds.minY, and: bounds.maxY - height),
                      width: width, height: height)
    }

    /// Move only the selected edges, retaining their opposite anchors without flipping.
    static func resized(_ rect: CGRect, handle: SelectionHandle, to point: CGPoint,
                        within bounds: CGRect, minimumSize: CGSize = CGSize(width: 24, height: 24)) -> CGRect {
        let rect = moved(rect, by: .zero, within: bounds)
        let bounds = bounds.standardized
        guard !rect.isNull, !bounds.isEmpty else { return .null }
        var left = rect.minX, right = rect.maxX
        var bottom = rect.minY, top = rect.maxY

        switch handle {
        case .topLeft, .left, .bottomLeft:
            let minimum = min(max(0, minimumSize.width), right - bounds.minX)
            left = clamped(point.x, between: bounds.minX, and: right - minimum)
        case .topRight, .right, .bottomRight:
            let minimum = min(max(0, minimumSize.width), bounds.maxX - left)
            right = clamped(point.x, between: left + minimum, and: bounds.maxX)
        default: break
        }
        switch handle {
        case .bottomLeft, .bottom, .bottomRight:
            let minimum = min(max(0, minimumSize.height), top - bounds.minY)
            bottom = clamped(point.y, between: bounds.minY, and: top - minimum)
        case .topLeft, .top, .topRight:
            let minimum = min(max(0, minimumSize.height), bounds.maxY - bottom)
            top = clamped(point.y, between: bottom + minimum, and: bounds.maxY)
        default: break
        }
        return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
    }

    /// Flip Cocoa coordinates into image pixels, retaining only pixels fully inside the selection.
    static func pixelCrop(for rect: CGRect, viewBounds: CGRect, imageSize: CGSize) -> CGRect {
        let bounds = viewBounds.standardized
        guard !bounds.isEmpty, !bounds.isInfinite,
              imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else { return .null }
        let selection = rect.standardized.intersection(bounds)
        guard !selection.isEmpty else { return .null }
        let scaleX = imageSize.width / bounds.width
        let scaleY = imageSize.height / bounds.height
        let left = ceil((selection.minX - bounds.minX) * scaleX)
        let right = floor((selection.maxX - bounds.minX) * scaleX)
        let top = ceil((bounds.maxY - selection.maxY) * scaleY)
        let bottom = floor((bounds.maxY - selection.minY) * scaleY)
        guard right > left, bottom > top else { return .null }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Clamp a coordinate to its permitted range.
    private static func clamped(_ value: CGFloat, between lower: CGFloat, and upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
