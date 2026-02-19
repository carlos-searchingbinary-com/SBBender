import SBBenderCore

// Disambiguate types that clash between SBBenderCore and dependency modules (MCP, MLXLMCommon).
// Public so they can be used in public API signatures within this module.
public typealias SBTool = SBBenderCore.Tool
public typealias SBMessage = SBBenderCore.Message
public typealias SBToolCallFormat = SBBenderCore.ToolCallFormat
