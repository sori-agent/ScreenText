import AppKit
import AnyLanguageModel
import XCTest

@testable import TRexLLM

final class UnifiedLanguageModelProviderTests: XCTestCase {
    func testPrepareOCRRequestPreservesOriginalPixelsAsPNG() throws {
        let request = try UnifiedLanguageModelProvider.prepareOCRRequest(
            image: makeTestImage(size: NSSize(width: 2200, height: 80)),
            prompt: nil
        )

        XCTAssertEqual(request.prompt, PromptTemplates.defaultOCRPrompt)
        XCTAssertEqual(request.mimeType, "image/png")
        XCTAssertEqual(Array(request.imageData.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        let decoded = try XCTUnwrap(NSBitmapImageRep(data: request.imageData))
        XCTAssertEqual(decoded.pixelsWide, 2200)
        XCTAssertEqual(decoded.pixelsHigh, 80)
    }

    func testPrepareOCRRequestUsesCustomPrompt() throws {
        let request = try UnifiedLanguageModelProvider.prepareOCRRequest(
            image: makeTestImage(),
            prompt: "  Read the vertical Japanese text.  "
        )

        XCTAssertEqual(request.prompt, "Read the vertical Japanese text.")
    }

    func testPrepareOCRRequestUsesDefaultForBlankPrompt() throws {
        let request = try UnifiedLanguageModelProvider.prepareOCRRequest(
            image: makeTestImage(),
            prompt: " \n "
        )

        XCTAssertEqual(request.prompt, PromptTemplates.defaultOCRPrompt)
    }

    func testPerformOCRUsesFreshSessionForEachCapture() async throws {
        let recorder = TranscriptRecorder()
        let provider = UnifiedLanguageModelProvider(model: RecordingLanguageModel(recorder: recorder))

        _ = try await provider.performOCR(image: makeTestImage(), prompt: nil, model: "test")
        _ = try await provider.performOCR(image: makeTestImage(), prompt: nil, model: "test")

        let summaries = await recorder.summaries
        XCTAssertEqual(summaries.map(\.entryCount), [1, 1])
        XCTAssertEqual(summaries.map(\.imageCount), [1, 1])
    }

    func testProcessTextUsesFreshSessionForEachCapture() async throws {
        let recorder = TranscriptRecorder()
        let provider = UnifiedLanguageModelProvider(model: RecordingLanguageModel(recorder: recorder))

        _ = try await provider.processText("first", prompt: "Clean: {text}", model: "test")
        _ = try await provider.processText("second", prompt: "Clean: {text}", model: "test")

        let summaries = await recorder.summaries
        XCTAssertEqual(summaries.map(\.entryCount), [1, 1])
        XCTAssertEqual(summaries.map(\.imageCount), [0, 0])
    }

    func testOpenRouterOCRRequiresFreeProvidersAndAllowsMandatoryReasoning() async throws {
        let recorder = TranscriptRecorder()
        let provider = UnifiedLanguageModelProvider(model: RecordingLanguageModel(recorder: recorder),
            endpoint: "https://openrouter.ai/api/v1")
        _ = try await provider.performOCR(image: makeTestImage(), prompt: nil, model: "stealth/space-bunny-alpha")
        let summaries = await recorder.summaries
        let options = try XCTUnwrap(summaries.first?.options)
        XCTAssertEqual(options.temperature, 0)
        let body = options[custom: OpenAILanguageModel.self]?.extraBody
        XCTAssertEqual(body?["provider"], .object(["max_price": .object(["prompt": .int(0), "completion": .int(0)])]))
        XCTAssertNil(body?["reasoning"])
    }

    func testQwenFlashOCRAllowsItsPublishedRatesWithoutReasoningOrModelFallback() async throws {
        let recorder = TranscriptRecorder()
        let provider = UnifiedLanguageModelProvider(model: RecordingLanguageModel(recorder: recorder),
            endpoint: "https://openrouter.ai/api/v1", modelName: "qwen/qwen3.7-flash")
        _ = try await provider.performOCR(image: makeTestImage(), prompt: nil, model: "qwen/qwen3.7-flash")
        let summaries = await recorder.summaries
        let options = try XCTUnwrap(summaries.first?.options)
        XCTAssertEqual(options.temperature, 0)
        let body = options[custom: OpenAILanguageModel.self]?.extraBody
        XCTAssertEqual(body?["provider"], .object(["max_price": .object(["prompt": .double(0.03), "completion": .double(0.13)])]))
        XCTAssertEqual(body?["reasoning"], .object(["enabled": .bool(false)]))
        XCTAssertNil(body?["models"])
    }

    func testEndpointValidationRequiresAbsoluteHTTPURL() {
        XCTAssertEqual(
            UnifiedLanguageModelProvider.validatedEndpoint("http://localhost:11434/v1")?.absoluteString,
            "http://localhost:11434/v1"
        )
        XCTAssertEqual(
            UnifiedLanguageModelProvider.validatedEndpoint("https://example.com/v1")?.absoluteString,
            "https://example.com/v1"
        )
        XCTAssertNil(UnifiedLanguageModelProvider.validatedEndpoint("relative/path"))
        XCTAssertNil(UnifiedLanguageModelProvider.validatedEndpoint("file:///tmp/socket"))
        XCTAssertNil(UnifiedLanguageModelProvider.validatedEndpoint("http://has space/v1"))
    }

    private func makeTestImage(size: NSSize = NSSize(width: 120, height: 80)) -> NSImage {
        // A bitmap gives fixed pixel dimensions on both Retina and ordinary displays.
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        return NSImage(cgImage: context.makeImage()!, size: size)
    }
}

private actor TranscriptRecorder {
    struct Summary: Sendable {
        let entryCount: Int
        let imageCount: Int
        let options: GenerationOptions
    }

    private(set) var summaries: [Summary] = []

    func record(_ transcript: Transcript, options: GenerationOptions) {
        let imageCount = transcript.reduce(into: 0) { count, entry in
            guard case .prompt(let prompt) = entry else { return }
            count += prompt.segments.filter {
                if case .image = $0 { return true }
                return false
            }.count
        }
        summaries.append(Summary(entryCount: transcript.count, imageCount: imageCount, options: options))
    }
}

private struct RecordingLanguageModel: LanguageModel {
    typealias UnavailableReason = Never

    let recorder: TranscriptRecorder

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        await recorder.record(session.transcript, options: options)
        let content = "recognized text"
        return LanguageModelSession.Response(
            content: content as! Content,
            rawContent: GeneratedContent(content),
            transcriptEntries: []
        )
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        fatalError("Streaming is not used by OCR tests")
    }
}
