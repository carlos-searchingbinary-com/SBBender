import Foundation

#if canImport(Speech)
@preconcurrency import Speech

/// Transcribes audio files to text using Apple's Speech framework.
///
/// Uses `SFSpeechRecognizer` + `SFSpeechURLRecognitionRequest` for offline
/// file-based transcription. For real-time streaming transcription, see
/// nolitai's `TranscriptionService` which uses `SpeechAnalyzer`.
///
/// Latency: Varies by file duration.
public struct TranscriptionSkill: NativeTool {
    public let id = "transcription"
    public let name = "transcribeAudio"
    public let description = "Transcribe an audio file (wav, m4a, mp3) to text"

    private let locale: Locale

    public init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    public var isAvailable: Bool {
        get async {
            let status = SFSpeechRecognizer.authorizationStatus()
            guard status == .authorized || status == .notDetermined else { return false }
            return SFSpeechRecognizer(locale: locale)?.isAvailable ?? false
        }
    }

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("Path to the audio file to transcribe (wav, m4a, mp3)"),
            ],
            required: ["input"]
        )
    }

    public func asTool() -> Tool {
        let skill = self
        return Tool(
            name: name,
            description: description,
            parameters: toolParameters
        ) { arguments, _ in
            struct Args: Decodable { let input: String }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let result = try await skill.execute(input: .text(args.input))
            return result.output
        }
    }

    /// Request speech recognition permission if not yet determined.
    private func ensureAccess() async throws {
        let status = SFSpeechRecognizer.authorizationStatus()
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted: Bool = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { newStatus in
                    continuation.resume(returning: newStatus == .authorized)
                }
            }
            guard granted else {
                throw SBBenderError.skillExecutionFailed(
                    skill: name,
                    reason: "Speech recognition access denied. Grant access in System Settings > Privacy & Security > Speech Recognition."
                )
            }
        default:
            throw SBBenderError.skillExecutionFailed(
                skill: name,
                reason: "Speech recognition access denied. Grant access in System Settings > Privacy & Security > Speech Recognition."
            )
        }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        guard let audioPath = input.text, !audioPath.isEmpty else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No audio file path provided")
        }

        try await ensureAccess()

        let url = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "Audio file not found: \(audioPath)")
        }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw SBBenderError.skillNotAvailable("Speech recognizer not available for locale: \(locale.identifier)")
        }

        let start = CFAbsoluteTimeGetCurrent()

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        // Extract only the needed data inside the callback to avoid
        // capturing the non-Sendable SFSpeechRecognitionResult across isolation boundaries.
        struct TranscriptionData: Sendable {
            let transcript: String
            let confidence: Float
            let segmentCount: Int
        }

        let data: TranscriptionData = try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: SBBenderError.skillExecutionFailed(
                        skill: "transcribeAudio", reason: error.localizedDescription
                    ))
                } else if let result, result.isFinal {
                    let segments = result.bestTranscription.segments
                    let avgConfidence = segments.reduce(0.0) { sum, seg in
                        sum + seg.confidence
                    } / max(Float(segments.count), 1)

                    continuation.resume(returning: TranscriptionData(
                        transcript: result.bestTranscription.formattedString,
                        confidence: avgConfidence,
                        segmentCount: segments.count
                    ))
                }
            }
        }

        return NativeToolResult(
            output: data.transcript,
            structuredData: [
                "segmentCount": String(data.segmentCount),
                "locale": locale.identifier,
            ],
            confidence: data.confidence,
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }
}
#endif
