import Foundation
import ImageIO
import Vision

/// Split script transitions for geometry; mixed Japanese/Korean rows need separate crops.
func scriptRanges(in text: String) -> [Range<String.Index>] {
    func script(of character: Character) -> Int? {
        for scalar in character.unicodeScalars {
            switch scalar.value {
            case 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF: return 1
            case 0x3040...0x30FF, 0xFF66...0xFF9D: return 2
            case 0x41...0x5A, 0x61...0x7A: return 3
            default: continue // Shared kanji, numbers, punctuation and spaces stay with their run.
            }
        }
        return nil
    }
    var start = text.startIndex
    var current: Int?
    var ranges: [Range<String.Index>] = []
    for index in text.indices {
        guard let next = script(of: text[index]) else { continue }
        if let previous = current, next != previous {
            ranges.append(start..<index)
            start = index
        }
        current = next
    }
    if start < text.endIndex { ranges.append(start..<text.endIndex) }
    return ranges
}

/// Return geometry only. Apple recognition is never copied as the OCR result.
func detectLines(in data: Data) throws -> [[String: Double]] {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "ScreenText", code: 1)
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.automaticallyDetectsLanguage = true
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0
    try VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).flatMap { observation -> [[String: Double]] in
        let topLeft = observation.topLeft
        let topRight = observation.topRight
        let angle = atan2(topRight.y - topLeft.y, topRight.x - topLeft.x)
        guard abs(angle) < .pi / 12 else { return [] }
        let candidate = observation.topCandidates(1).first
        let ranges = candidate.map { scriptRanges(in: $0.string) } ?? []
        let boxes: [CGRect]
        if let candidate, ranges.count > 1 {
            boxes = ranges.compactMap { try? candidate.boundingBox(for: $0)?.boundingBox }
        } else {
            boxes = [observation.boundingBox]
        }
        return boxes.map { box in ["x": box.minX * Double(image.width),
                "y": (1 - box.maxY) * Double(image.height),
                "width": box.width * Double(image.width),
                "height": box.height * Double(image.height)] }
    }
}

do {
    let rectangles = try detectLines(in: FileHandle.standardInput.readDataToEndOfFile())
    FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: rectangles))
} catch {
    FileHandle.standardError.write(Data("Text region detection failed.\n".utf8))
    exit(1)
}
