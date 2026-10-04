import AppKit
import Vision
import XCTest
@testable import TRexCore

/// A local model failure must leave the result empty when fallback is disabled.
@MainActor
final class LocalOCRFailureTests: XCTestCase {
    func testLocalModelFailureDoesNotSilentlyUseVision() async throws {
        try await verifyLocalFailure(automaticDetection: false)
    }

    func testAutomaticLanguageDetectionDoesNotBypassTheLocalModel() async throws {
        try await verifyLocalFailure(automaticDetection: true)
    }

    private func verifyLocalFailure(automaticDetection: Bool) async throws {
        let preferences = Preferences.shared
        let saved = (preferences.llmEnabled, preferences.llmEnableOCR,
                     preferences.llmOCRProvider, preferences.llmOCRCustomEndpoint,
                     preferences.llmOCRModel, preferences.llmFallbackToBuiltIn,
                     preferences.automaticLanguageDetection, preferences.tesseractEnabled,
                     preferences.tableDetectionEnabled)
        let originalVision = try XCTUnwrap(OCRManager.shared.engines.first { $0.identifier == "vision" })
        defer {
            (preferences.llmEnabled, preferences.llmEnableOCR,
             preferences.llmOCRProvider, preferences.llmOCRCustomEndpoint,
             preferences.llmOCRModel, preferences.llmFallbackToBuiltIn,
             preferences.automaticLanguageDetection, preferences.tesseractEnabled,
             preferences.tableDetectionEnabled) = saved
            OCRManager.shared.registerEngine(originalVision)
            TRex.shared.initializeLLM()
        }
        OCRManager.shared.registerEngine(FallbackVision())
        preferences.llmEnabled = true
        preferences.llmEnableOCR = true
        preferences.llmOCRProvider = "Custom"
        preferences.llmOCRCustomEndpoint = "http://127.0.0.1:1/v1"
        preferences.llmOCRModel = "unavailable-test-model"
        preferences.llmFallbackToBuiltIn = false
        preferences.automaticLanguageDetection = automaticDetection
        preferences.tesseractEnabled = false
        preferences.tableDetectionEnabled = false
        TRex.shared.initializeLLM()
        let context = try XCTUnwrap(CGContext(data: nil, width: 24, height: 12,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())

        let result = await TRex.shared.recognizeImageForWatchMode(image)

        XCTAssertNil(result, "An unavailable local model must not return another engine's text.")
    }
}

private struct FallbackVision: OCREngine {
    let name = "Test Vision"
    let identifier = "vision"
    let priority = 50
    func supportsLanguage(_ language: String) -> Bool { true }
    func recognizeText(in image: CGImage, languages: [String], recognitionLevel: VNRequestTextRecognitionLevel) async throws -> OCRResult {
        OCRResult(text: "unexpected fallback", confidence: 1, recognizedLanguages: languages)
    }
    func recognizeText(in image: CGImage, recognitionLevel: VNRequestTextRecognitionLevel) async throws -> OCRResult {
        try await recognizeText(in: image, languages: [], recognitionLevel: recognitionLevel)
    }
}
