# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**SBBender** is a Swift agent runtime inspired by [Agno](../agno) (Python). It provides a production-grade framework for building multimodal AI agents, agent swarms, and workflows — all native to Apple platforms. The runtime will eventually replace the agents in [nolitai/core](../nolitai/core), a macOS meeting copilot.

### Design Goals

- **Swift 6 with strict concurrency** — all public APIs must be `Sendable`-safe
- **Async-first** — every public method is `async`, no sync wrappers needed (unlike Agno's dual sync/async)
- **Protocol-oriented** — extensibility through Swift protocols, not class inheritance
- **Apple-native skills** — agents use Apple frameworks (NaturalLanguage, Speech, Vision, Translation, ScreenCaptureKit, EventKit) as first-class skills
- **On-device inference** — MLX Swift for local LLMs and vision models on Apple Silicon
- **Multimodal from day one** — text, image, audio, video as first-class message content types

## Architecture

### Core Abstractions (mapped from Agno → Swift)

| Agno (Python) | SBBender (Swift) | Notes |
|---|---|---|
| `Agent` | `Agent` | Actor-based, generic over `Model` provider |
| `Team` | `Swarm` | Autonomous, sequential, parallel execution modes |
| `Workflow` | `Workflow` | Structured concurrency with `TaskGroup` |
| `Model` (base) | `ModelProvider` protocol | Unified interface for all LLM providers |
| `Toolkit` | `ToolKit` protocol | Groups related `Tool` definitions |
| `Skill` | `Skill` protocol | Apple-native capabilities (NLP, Vision, Audio) |
| `Function` | `Tool` | JSON Schema parameters, confirmation support |
| `Knowledge` | `KnowledgeSource` protocol | RAG or RAGless (PageTree from nolitai) |
| `LearningMachine` | `LearningEngine` | User profile, memory, entity, session stores |
| `BaseDb` | `StorageBackend` protocol | GRDB/SQLite primary, not Postgres |
| `Message` | `Message` | Multimodal content with `MediaAttachment` enum |
| `RunOutput` | `RunResult` | Structured output via `Codable` generics |

### Model Provider Hierarchy

```
ModelProvider (protocol)
├── MLXProvider          — Local Qwen3/Llama via MLX Swift (primary)
├── FoundationProvider   — Apple Intelligence (FoundationModels framework, macOS 26+)
├── AnthropicProvider    — Claude API
├── OpenAIProvider       — OpenAI-compatible APIs
└── OllamaProvider       — Local models via Ollama HTTP
```

MLX is the default provider. FoundationProvider is the automatic fallback. Cloud providers require explicit opt-in.

### Skill System (Apple Automations)

Skills wrap Apple frameworks as zero-latency, no-LLM-needed capabilities:

| Skill | Apple Framework | Latency |
|---|---|---|
| `LanguageDetectionSkill` | NaturalLanguage | <1ms |
| `SentimentSkill` | NaturalLanguage | <1ms |
| `EntityExtractionSkill` | NaturalLanguage | <1ms |
| `TranscriptionSkill` | Speech | Real-time |
| `TranslationSkill` | Translation | <100ms |
| `VisionSkill` | Vision + MLX-VL | ~1s |
| `ScreenCaptureSkill` | ScreenCaptureKit | Real-time |
| `CalendarSkill` | EventKit | <10ms |
| `RemindersSkill` | EventKit | <10ms |
| `ShortcutsSkill` | AppIntents / Shortcuts | Varies |
| `AppleScriptSkill` | NSAppleScript | Varies |

Skills are distinct from Tools: a Skill provides instant native capability; a Tool is an LLM-callable function with JSON Schema.

### Swarm Execution Modes

```swift
enum SwarmMode {
    case autonomous   // Leader agent delegates via LLM reasoning
    case sequential   // Execute members in order
    case parallel     // Execute all members concurrently (TaskGroup)
    case route(Router) // Dynamic routing based on input
}
```

### Message & Media Model

```swift
struct Message: Sendable, Codable {
    let role: Role           // .system, .user, .assistant, .tool
    let content: [Content]   // Text + media in a single message
    let toolCalls: [ToolCall]?
}

enum Content: Sendable, Codable {
    case text(String)
    case image(ImageContent)    // URL, file path, or raw bytes
    case audio(AudioContent)
    case video(VideoContent)
    case file(FileContent)
}
```

### Storage

Primary storage is **GRDB + SQLite** (not Postgres). Tables mirror Agno's schema:
- `sessions` — chat history and session state
- `memories` — user memories
- `learnings` — learning store data
- `knowledge` — content tracking for RAG

### Package Structure

```
Sources/
├── SBBender/           # Core runtime library
│   ├── Agent/          # Agent actor, run loop, context
│   ├── Swarm/          # Multi-agent coordination
│   ├── Workflow/       # Step-based orchestration
│   ├── Model/          # Provider protocols and implementations
│   ├── Tool/           # Tool protocol, registry, execution
│   ├── Skill/          # Apple-native skills
│   ├── Knowledge/      # RAG and PageTree
│   ├── Learning/       # Memory and learning stores
│   ├── Storage/        # GRDB backend
│   ├── Media/          # Multimodal content types
│   └── Message/        # Message protocol and types
└── SBBenderTests/      # XCTest + Swift Testing
```

## Build & Development

```bash
# Build
swift build

# Run tests
swift test

# Run a single test
swift test --filter SBBenderTests.AgentTests/testBasicRun

# Build for release
swift build -c release
```

### Platform Requirements

- macOS 14+ (Sonoma) minimum deployment target
- Swift 6.0+ toolchain
- Xcode 16+ for development
- Apple Silicon recommended (required for MLX inference)

### Key Dependencies

- **MLX Swift** (apple/mlx-swift) — on-device inference
- **MLX LLM** — model architectures (Qwen3, etc.)
- **GRDB** (groue/GRDB.swift) — SQLite with FTS5
- Apple frameworks: NaturalLanguage, Speech, Vision, Translation, FoundationModels, ScreenCaptureKit, EventKit

## Conventions

- Use Swift `actor` for `Agent` (not `class`) to guarantee thread safety
- All protocols should be marked `Sendable`
- Prefer `AsyncStream` for streaming responses over callbacks/delegates
- Use `TaskGroup` for parallel execution in swarms, not `DispatchQueue`
- JSON Schema for tool parameters — generate from `Codable` types via reflection or macros
- Errors should be typed enums conforming to `LocalizedError`
- Use `os.Logger` (subsystem: `com.sbbender`) for logging, not `print`

## Relationship to Reference Codebases

- **Agno** (`../agno`): The Python blueprint. Port core abstractions (Agent, Team→Swarm, Workflow, Tool, Knowledge, Learning) but adapt to Swift idioms. Do NOT port: FastAPI runtime, Python-specific patterns (dataclasses, decorators), sync wrappers.
- **nolitai/core** (`../nolitai/core`): The target integration. SBBender will replace nolitai's agent system (AgentProtocol, VisionAgentProtocol, AgentOrchestrator, all specialized agents). Preserve nolitai's Apple-native skills, MLX provider, PageTree knowledge system, and GRDB storage patterns.
