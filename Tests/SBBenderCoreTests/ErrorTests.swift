import Testing
import Foundation
@testable import SBBenderCore

@Suite("SBBenderError Tests")
struct ErrorTests {

    @Test("All errors have descriptions")
    func testErrorDescriptions() {
        let errors: [SBBenderError] = [
            .modelNotLoaded,
            .modelNotAvailable("test"),
            .generationFailed("reason"),
            .allProvidersFailed(["a", "b"]),
            .toolNotFound("tool"),
            .toolExecutionFailed(tool: "t", reason: "r"),
            .invalidArguments("bad"),
            .toolCallLimitExceeded(10),
            .agentNotReady("reason"),
            .runCancelled,
            .maxIterationsExceeded(5),
            .storageError("db"),
            .sessionNotFound("s1"),
            .migrationFailed("v1"),
            .knowledgeInsertFailed("reason"),
            .knowledgeSearchFailed("reason"),
            .skillNotAvailable("skill"),
            .skillExecutionFailed(skill: "s", reason: "r"),
            .swarmDelegationFailed("reason"),
            .memberNotFound("member"),
            .workflowStepFailed(step: "step", reason: "r"),
            .invalidConfiguration("bad"),
            .jsonParsingFailed("reason"),
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("Error is LocalizedError")
    func testLocalizedError() {
        let error: any LocalizedError = SBBenderError.modelNotLoaded
        #expect(error.errorDescription != nil)
    }
}
