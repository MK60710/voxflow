import Foundation
import Testing
@testable import VoxFlowCore

@Suite("GroqMultipartRequestBuilder")
struct GroqMultipartRequestBuilderTests {

    static let baseURL = URL(string: "https://api.groq.com/openai/v1")!

    @Test("request targets the correct endpoint, method, and headers")
    func requestTargetsCorrectEndpoint() {
        let (request, _) = GroqMultipartRequestBuilder.build(
            baseURL: Self.baseURL,
            apiKey: "test-key-123",
            model: "whisper-large-v3-turbo",
            language: nil,
            prompt: nil,
            audioData: Data([0x01, 0x02]),
            audioFileName: "recording.wav",
            boundary: "TESTBOUNDARY"
        )

        #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/audio/transcriptions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key-123")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=TESTBOUNDARY")
    }

    @Test("whisper-large-v3-turbo gets verbose_json response format (needed for the hallucination filter)")
    func turboModelGetsVerboseJSON() {
        #expect(GroqMultipartRequestBuilder.responseFormat(forModel: "whisper-large-v3-turbo") == "verbose_json")
        #expect(GroqMultipartRequestBuilder.responseFormat(forModel: "WHISPER-LARGE-V3-TURBO") == "verbose_json")
    }

    @Test("an unrecognized model falls back to plain json response format")
    func unknownModelGetsPlainJSON() {
        #expect(GroqMultipartRequestBuilder.responseFormat(forModel: "some-future-model") == "json")
    }

    @Test("body includes the model field with the correct value")
    func bodyIncludesModelField() {
        let (_, body) = GroqMultipartRequestBuilder.build(
            baseURL: Self.baseURL,
            apiKey: "key",
            model: "whisper-large-v3-turbo",
            language: nil,
            prompt: nil,
            audioData: Data([0xAA]),
            audioFileName: "a.wav",
            boundary: "B"
        )
        let bodyString = String(data: body, encoding: .isoLatin1) ?? ""
        #expect(bodyString.contains("name=\"model\""))
        #expect(bodyString.contains("whisper-large-v3-turbo"))
        #expect(bodyString.contains("name=\"response_format\""))
        #expect(bodyString.contains("verbose_json"))
    }

    @Test("language field is omitted when nil")
    func languageOmittedWhenNil() {
        let (_, body) = GroqMultipartRequestBuilder.build(
            baseURL: Self.baseURL,
            apiKey: "key",
            model: "whisper-large-v3-turbo",
            language: nil,
            prompt: nil,
            audioData: Data([0xAA]),
            audioFileName: "a.wav",
            boundary: "B"
        )
        let bodyString = String(data: body, encoding: .isoLatin1) ?? ""
        #expect(!bodyString.contains("name=\"language\""))
    }

    @Test("language field is included when provided")
    func languageIncludedWhenProvided() {
        let (_, body) = GroqMultipartRequestBuilder.build(
            baseURL: Self.baseURL,
            apiKey: "key",
            model: "whisper-large-v3-turbo",
            language: "en",
            prompt: nil,
            audioData: Data([0xAA]),
            audioFileName: "a.wav",
            boundary: "B"
        )
        let bodyString = String(data: body, encoding: .isoLatin1) ?? ""
        #expect(bodyString.contains("name=\"language\""))
        #expect(bodyString.contains("\r\nen\r\n"))
    }

    @Test("prompt (dictionary bias) field is included when provided, omitted when nil")
    func promptFieldIncludedOnlyWhenProvided() {
        let (_, bodyWithPrompt) = GroqMultipartRequestBuilder.build(
            baseURL: Self.baseURL, apiKey: "key", model: "whisper-large-v3-turbo",
            language: nil, prompt: "CogniSwitch, ContextOps",
            audioData: Data([0xAA]), audioFileName: "a.wav", boundary: "B"
        )
        let withPromptString = String(data: bodyWithPrompt, encoding: .isoLatin1) ?? ""
        #expect(withPromptString.contains("name=\"prompt\""))
        #expect(withPromptString.contains("CogniSwitch, ContextOps"))

        let (_, bodyNoPrompt) = GroqMultipartRequestBuilder.build(
            baseURL: Self.baseURL, apiKey: "key", model: "whisper-large-v3-turbo",
            language: nil, prompt: nil,
            audioData: Data([0xAA]), audioFileName: "a.wav", boundary: "B"
        )
        let noPromptString = String(data: bodyNoPrompt, encoding: .isoLatin1) ?? ""
        #expect(!noPromptString.contains("name=\"prompt\""))
    }

    @Test("audio bytes are embedded in the file field verbatim, with the correct content type")
    func audioBytesEmbeddedVerbatim() {
        let audioBytes = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xFF])
        let (_, body) = GroqMultipartRequestBuilder.build(
            baseURL: Self.baseURL,
            apiKey: "key",
            model: "whisper-large-v3-turbo",
            language: nil,
            prompt: nil,
            audioData: audioBytes,
            audioFileName: "recording.wav",
            boundary: "B"
        )
        #expect(body.range(of: audioBytes) != nil)

        let bodyPrefixString = String(data: body, encoding: .isoLatin1) ?? ""
        #expect(bodyPrefixString.contains("filename=\"recording.wav\""))
        #expect(bodyPrefixString.contains("Content-Type: audio/wav"))
    }

    @Test("audio content type is inferred from file extension")
    func contentTypeInferredFromExtension() {
        #expect(GroqMultipartRequestBuilder.audioContentType(forFileName: "x.wav") == "audio/wav")
        #expect(GroqMultipartRequestBuilder.audioContentType(forFileName: "x.mp3") == "audio/mpeg")
        #expect(GroqMultipartRequestBuilder.audioContentType(forFileName: "x.m4a") == "audio/mp4")
        #expect(GroqMultipartRequestBuilder.audioContentType(forFileName: "x.unknown") == "audio/mp4")
    }

    @Test("body starts and ends with the correct boundary markers")
    func bodyStartsAndEndsWithBoundary() {
        let (_, body) = GroqMultipartRequestBuilder.build(
            baseURL: Self.baseURL, apiKey: "key", model: "whisper-large-v3-turbo",
            language: nil, prompt: nil, audioData: Data([0x01]), audioFileName: "a.wav", boundary: "B"
        )
        let bodyString = String(data: body, encoding: .isoLatin1) ?? ""
        #expect(bodyString.hasPrefix("--B\r\n"))
        #expect(bodyString.hasSuffix("--B--\r\n"))
    }
}
