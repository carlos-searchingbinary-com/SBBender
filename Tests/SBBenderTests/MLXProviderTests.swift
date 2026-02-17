import Testing
import Foundation
@testable import SBBender

@Suite("MLXProvider Helper Tests")
struct MLXProviderHelperTests {

    @Test("Build ChatML prompt from messages")
    func testBuildPrompt() {
        let messages: [Message] = [
            .system("You are a helpful assistant"),
            .user("Hello"),
            .assistant("Hi there!"),
            .user("How are you?"),
        ]

        let prompt = MLXProvider.buildPrompt(from: messages)

        #expect(prompt.contains("<|im_start|>system"))
        #expect(prompt.contains("You are a helpful assistant"))
        #expect(prompt.contains("<|im_end|>"))
        #expect(prompt.contains("<|im_start|>user"))
        #expect(prompt.contains("Hello"))
        #expect(prompt.contains("<|im_start|>assistant"))
        #expect(prompt.contains("Hi there!"))
        #expect(prompt.hasPrefix("<|im_start|>system"))
        #expect(prompt.hasSuffix("<|im_start|>assistant\n"))
    }

    @Test("Strip thinking tags - with tags")
    func testStripThinkingTags() {
        let input = "<think>Let me think about this...</think>The answer is 42."
        let result = MLXProvider.stripThinkingTags(input)
        #expect(result == "The answer is 42.")
    }

    @Test("Strip thinking tags - no tags")
    func testStripNoTags() {
        let input = "Just a normal response."
        let result = MLXProvider.stripThinkingTags(input)
        #expect(result == "Just a normal response.")
    }

    @Test("Strip thinking tags - only thinking")
    func testStripOnlyThinking() {
        let input = "<think>Just thinking, no output</think>"
        let result = MLXProvider.stripThinkingTags(input)
        #expect(result == "")
    }

    @Test("Strip thinking tags - unclosed think tag")
    func testStripUnclosedThink() {
        let input = "<think>Still thinking..."
        let result = MLXProvider.stripThinkingTags(input)
        #expect(result == "")
    }

    @Test("Strip thinking tags - multiline thinking")
    func testStripMultilineThinking() {
        let input = """
        <think>
        Let me reason step by step:
        1. First consideration
        2. Second consideration
        </think>
        Based on my analysis, the answer is correct.
        """
        let result = MLXProvider.stripThinkingTags(input)
        #expect(result == "Based on my analysis, the answer is correct.")
    }
}

@Suite("ModelMetrics Tests")
struct ModelMetricsTests {

    @Test("RunMetrics accumulate model metrics")
    func testAccumulate() {
        var runMetrics = RunMetrics()

        let m1 = ModelMetrics(inputTokens: 10, outputTokens: 20, totalTokens: 30, latency: 1.0)
        let m2 = ModelMetrics(inputTokens: 15, outputTokens: 25, totalTokens: 40, latency: 0.5)

        runMetrics.accumulate(m1)
        runMetrics.accumulate(m2)

        #expect(runMetrics.totalInputTokens == 25)
        #expect(runMetrics.totalOutputTokens == 45)
        #expect(runMetrics.totalTokens == 70)
        #expect(runMetrics.modelCalls == 2)
    }
}

@Suite("GenerationConfig Tests")
struct GenerationConfigTests {

    @Test("Default config values")
    func testDefaults() {
        let config = GenerationConfig()
        #expect(config.maxTokens == 2048)
        #expect(config.temperature == 0.7)
        #expect(config.topP == 0.9)
        #expect(config.enableThinking == false)
    }

    @Test("Custom config")
    func testCustom() {
        let config = GenerationConfig(
            maxTokens: 4096,
            temperature: 0.0,
            topP: 1.0,
            enableThinking: true
        )
        #expect(config.maxTokens == 4096)
        #expect(config.temperature == 0.0)
        #expect(config.enableThinking == true)
    }
}
