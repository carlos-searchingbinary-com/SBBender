import Foundation
import SwiftUI
import SBBender

@MainActor
@Observable
final class SkillLabViewModel {
    // MARK: - Skill Mode (SKILL.md through agent)

    var installedSkills: [Skill] = []
    var selectedSkillID: String?
    var selectedProvider: ProviderType = .ollama
    var selectedModelID: String = "qwen3:4b"
    var enabledToolIDs: Set<String> = []
    var inputText: String = ""
    var agentResponse: String = ""
    var isRunning: Bool = false
    var errorMessage: String?
    var responseLatency: TimeInterval = 0
    var responseTokens: Int = 0

    // MARK: - Native Tool Mode (direct execution)

    var labMode: LabMode = .skill

    var selectedNativeToolID: String?
    var nativeToolInput: String = ""
    var nativeToolParameters: [String: String] = [:]
    var nativeToolOutput: String = ""
    var nativeToolStructuredData: [String: String] = [:]
    var nativeToolConfidence: Float = 0
    var nativeToolLatency: TimeInterval = 0

    enum LabMode: String, CaseIterable {
        case skill = "Skill"
        case nativeTool = "Native Tool"
    }

    // MARK: - Load Installed Skills

    func loadInstalledSkills(appState: AppState) async {
        do {
            let client = appState.skillsShClient
            installedSkills = try await client.listInstalled()

            // Pre-select native tools based on skill's allowedTools
            if let id = selectedSkillID,
               let skill = installedSkills.first(where: { $0.id == id }),
               let allowed = skill.allowedTools {
                enabledToolIDs = Set(allowed)
            }
        } catch {
            errorMessage = "Failed to load skills: \(error.localizedDescription)"
        }
    }

    // MARK: - Run Skill (through agent)

    func runSkill(appState: AppState) async {
        guard let id = selectedSkillID,
              let skill = installedSkills.first(where: { $0.id == id }) else { return }

        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isRunning = true
        errorMessage = nil
        agentResponse = ""
        responseLatency = 0
        responseTokens = 0

        let start = CFAbsoluteTimeGetCurrent()

        do {
            let provider = AgentFactory.createProvider(
                type: selectedProvider,
                modelID: selectedModelID
            )

            // Filter native tools based on selection
            let selectedNativeTools = appState.nativeSkills.filter { enabledToolIDs.contains($0.id) }

            let config = AgentConfiguration(
                name: skill.name,
                instructions: skill.instructions
            )

            let agent = Agent(
                configuration: config,
                model: provider,
                nativeTools: selectedNativeTools,
                skills: [skill]
            )

            let result = try await agent.run(text)
            agentResponse = result.content
            responseLatency = result.metrics.totalLatency
            responseTokens = result.metrics.totalOutputTokens
        } catch {
            errorMessage = error.localizedDescription
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        if responseLatency == 0 { responseLatency = elapsed }
        isRunning = false
    }

    // MARK: - Run Native Tool (direct)

    func runNativeTool(nativeTools: [any NativeTool]) async {
        guard let id = selectedNativeToolID,
              let tool = nativeTools.first(where: { $0.id == id }) else { return }

        let text = nativeToolInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isRunning = true
        errorMessage = nil
        nativeToolOutput = ""
        nativeToolStructuredData = [:]

        do {
            var allParams = nativeToolParameters
            allParams["input"] = text
            let input = NativeToolInput(text: text, parameters: allParams)
            let result = try await tool.execute(input: input)

            nativeToolOutput = result.output
            nativeToolStructuredData = result.structuredData
            nativeToolConfidence = result.confidence
            nativeToolLatency = result.latency
        } catch {
            errorMessage = error.localizedDescription
        }

        isRunning = false
    }

    // MARK: - Skill Selection

    func onSkillSelected(appState: AppState) {
        guard let id = selectedSkillID,
              let skill = installedSkills.first(where: { $0.id == id }) else {
            enabledToolIDs = []
            return
        }

        // Pre-enable tools based on skill's allowedTools
        if let allowed = skill.allowedTools {
            enabledToolIDs = Set(allowed)
        } else {
            // Enable all by default
            enabledToolIDs = Set(appState.nativeSkills.map(\.id))
        }
    }
}
