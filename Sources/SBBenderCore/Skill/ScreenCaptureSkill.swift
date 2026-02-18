import Foundation

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit

/// Captures screenshots of the current display using ScreenCaptureKit.
///
/// Returns the image as base64-encoded PNG data with dimensions.
///
/// Latency: <100ms.
@available(macOS 14, *)
public struct ScreenCaptureSkill: NativeTool {
    public let id = "screencapture"
    public let name = "captureScreen"
    public let description = "Capture a screenshot of the current display"

    public init() {}

    public var isAvailable: Bool {
        get async { true }
    }

    public var toolParameters: JSONSchema {
        JSONSchema(
            properties: [
                "input": .string("Display index to capture (default: '0' for main display)"),
            ],
            required: []
        )
    }

    public func asTool() -> Tool {
        let skill = self
        return Tool(
            name: name,
            description: description,
            parameters: toolParameters
        ) { arguments, _ in
            struct Args: Decodable { let input: String? }
            let args = try JSONDecoder().decode(Args.self, from: Data(arguments.utf8))
            let result = try await skill.execute(input: .text(args.input ?? "0"))
            var response: [String: String] = [
                "output": result.output,
                "width": result.structuredData["width"] ?? "",
                "height": result.structuredData["height"] ?? "",
                "sizeBytes": result.structuredData["sizeBytes"] ?? "",
            ]
            // Omit base64 from tool result to avoid flooding context window
            response["base64_available"] = "true"
            if let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys]),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return result.output
        }
    }

    public func execute(input: NativeToolInput) async throws -> NativeToolResult {
        let start = CFAbsoluteTimeGetCurrent()

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "No displays found")
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        // Convert CGImage to base64 PNG
        let width = image.width
        let height = image.height

        let bitmapRep = NSBitmapImageRep(cgImage: image)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            throw SBBenderError.skillExecutionFailed(skill: name, reason: "Failed to encode screenshot as PNG")
        }

        let base64 = pngData.base64EncodedString()

        return NativeToolResult(
            output: "Screenshot captured: \(width)x\(height)",
            structuredData: [
                "width": String(width),
                "height": String(height),
                "format": "png",
                "base64": base64,
                "sizeBytes": String(pngData.count),
            ],
            confidence: 1.0,
            latency: CFAbsoluteTimeGetCurrent() - start
        )
    }
}

import AppKit

private extension ScreenCaptureSkill {
    // NSBitmapImageRep used for PNG encoding requires AppKit
}
#endif
