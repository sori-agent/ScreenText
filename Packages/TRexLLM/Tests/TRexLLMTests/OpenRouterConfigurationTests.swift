import XCTest
@testable import TRexLLM

final class OpenRouterConfigurationTests: XCTestCase {
    func testOpenRouterUsesItsOwnEnvironmentKey() {
        let configuration = LLMConfiguration(ocrProvider: .custom,
            ocrCustomEndpoint: "https://openrouter.ai/api/v1")
        XCTAssertEqual(configuration.resolveOCRAPIKey(environment: ["OPENROUTER_API_KEY": "test-router-key"]), "test-router-key")
    }

    func testOpenRouterKeyIsNotSentToAnotherCustomEndpoint() {
        let configuration = LLMConfiguration(ocrProvider: .custom,
            ocrCustomEndpoint: "http://127.0.0.1:18871/v1")
        XCTAssertNil(configuration.resolveOCRAPIKey(environment: ["OPENROUTER_API_KEY": "test-router-key"]))
    }

    func testOpenRouterEnvironmentKeyRequiresHTTPS() {
        let configuration = LLMConfiguration(ocrProvider: .custom,
            ocrCustomEndpoint: "http://openrouter.ai/api/v1")
        XCTAssertNil(configuration.resolveOCRAPIKey(environment: ["OPENROUTER_API_KEY": "test-router-key"]))
    }
}
