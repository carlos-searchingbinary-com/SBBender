# SBBender Gap Remediation — Phased Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close all identified gaps across the core library and SwiftUI app, phased by impact to end users.

**Architecture:** Fix critical blockers first (Phase 1), then provider reliability (Phase 2), then UX polish (Phase 3), then advanced features (Phase 4).

**Tech Stack:** Swift 6, SwiftUI, MLXLMCommon, GRDB, DuckDB, MCP Swift SDK

---

## Phase 1: Critical Blockers (Users Can't Use the App)

These are the gaps that make the app unusable for a normal person. Fix all of these before anything else.

---

### Task 1: Markdown Rendering in Chat Bubbles

**Files:**
- Modify: `Sources/SBBenderApp/Views/Components/ChatBubble.swift:66-91`
- Exists: `Sources/SBBenderApp/Views/Components/MarkdownView.swift`

**Context:** `ChatBubble.messageContent` uses `Text(message.content)` for all roles. `MarkdownView` already exists and renders markdown via `AttributedString`. The fix is to use `MarkdownView` for assistant messages instead of plain `Text`.

**Step 1: Write the change**

In `ChatBubble.swift`, replace the three `Text(message.content)` / `Text(before)` / `Text(after)` calls for assistant roles with `MarkdownView(content:)`:

```swift
@ViewBuilder
private var messageContent: some View {
    if isAssistantRole, let (before, chartSpec, after) = extractChart(from: message.content) {
        if !before.isEmpty {
            MarkdownView(content: before)
                .font(.body)
        }
        ChartRendererView(spec: chartSpec)
        if !after.isEmpty {
            MarkdownView(content: after)
                .font(.body)
        }
    } else if message.role == "assistant-streaming" {
        HStack(spacing: 0) {
            MarkdownView(content: message.content)
                .font(.body)
            BlinkingCursor()
        }
    } else if isAssistantRole {
        MarkdownView(content: message.content)
            .font(.body)
    } else {
        Text(message.content)
            .textSelection(.enabled)
            .font(.body)
    }
}
```

Keep `Text()` for user messages (they don't need markdown rendering).

**Step 2: Build and verify**

Run: `swift build`
Expected: Clean compile.

**Step 3: Commit**

```bash
git add Sources/SBBenderApp/Views/Components/ChatBubble.swift
git commit -m "feat(chat): render assistant messages with markdown"
```

---

### Task 2: Native Tool Picker in Agent Builder

**Files:**
- Modify: `Sources/SBBenderApp/Views/Agents/AgentBuilderSheet.swift` (capabilitiesStep)
- Modify: `Sources/SBBenderApp/Models/AgentConfig.swift` (ensure enabledSkillIDs persists)
- Read: `Sources/SBBenderApp/Services/AppState.swift:399-416` (nativeToolsForConfig reference)

**Context:** `AgentBuilderSheet` has no UI for `enabledSkillIDs`. All agents silently get all 18 native tools. Need a toggle grid in the Capabilities step showing each native tool with name, icon, and on/off toggle. The list of native tools comes from `AppState.nativeSkills` (line 58).

**Step 1: Add state variable**

Add `@State private var enabledNativeToolIDs: Set<String>` initialized from the config's `enabledSkillIDs` (or all tools if empty for backward compat).

**Step 2: Add the native tools section to capabilitiesStep**

After the existing skills picker section, add a "Tools" section with a `LazyVGrid` of toggle-able tool cards. Each card shows:
- Tool icon (map from ID: "calendar" → calendar, "shell" → terminal, etc.)
- Tool name (human-readable, not the raw ID)
- Toggle switch
- One-line description

Group them: "Data" (data-analysis, web-fetch, entity-extraction), "Productivity" (calendar, reminders, email, shortcuts), "System" (shell, applescript, screen-capture), "AI" (charting, vision, transcription, translation, embedding-distance).

**Step 3: Wire up save**

In the save function, set `agent.enabledSkillIDs = Array(enabledNativeToolIDs)`.

**Step 4: Update AgentCard display**

Replace "All tools enabled" with actual count: "5 tools" or specific names if ≤ 3.

**Step 5: Build and verify**

Run: `swift build`

**Step 6: Commit**

```bash
git add Sources/SBBenderApp/Views/Agents/AgentBuilderSheet.swift Sources/SBBenderApp/Models/AgentConfig.swift
git commit -m "feat(builder): add native tool picker to agent capabilities step"
```

---

### Task 3: OllamaProvider — Fix Streaming Tool Calls

**Files:**
- Modify: `Sources/SBBender/Model/OllamaProvider.swift:171-194`
- Test: `Tests/SBBenderTests/OllamaProviderTests.swift` (add streaming tool call test)

**Context:** The `generateStream` path reads `messageDict["content"]` but never reads `messageDict["tool_calls"]`. The non-streaming `generate` correctly calls `parseToolCalls(from: messageDict)`. The fix mirrors the non-streaming path: check for `tool_calls` in each streaming chunk and in the final `done` chunk.

Ollama streaming with tools: tool calls appear in the `message.tool_calls` field of streaming chunks when the model decides to call a tool. They accumulate across chunks. The final chunk (`"done": true`) has the complete message.

**Step 1: Write failing test**

```swift
@Test("Streaming path emits tool calls from Ollama response")
func testStreamingToolCalls() async throws {
    // Mock Ollama streaming response with tool_calls in message
    // ...
}
```

**Step 2: Fix the streaming loop**

In the `for try await line in bytes.lines` loop, after checking for content, add:

```swift
if let messageDict = json["message"] as? [String: Any],
   let toolCallsArray = messageDict["tool_calls"] as? [[String: Any]] {
    let parsed = parseToolCalls(from: messageDict)
    for tc in parsed {
        continuation.yield(.toolCall(tc))
    }
}
```

Also add `repeat_penalty` to the streaming options dict (missing, present in non-streaming).

**Step 3: Run tests**

Run: `swift test --filter OllamaProvider`

**Step 4: Commit**

```bash
git add Sources/SBBender/Model/OllamaProvider.swift Tests/SBBenderTests/OllamaProviderTests.swift
git commit -m "fix(ollama): emit tool calls in streaming path"
```

---

### Task 4: Clear Chat Confirmation Dialog

**Files:**
- Modify: `Sources/SBBenderApp/Views/Agents/AgentChatView.swift` (trash button + new chat button)

**Context:** Both the trash toolbar button and the "New Chat" button call `viewModel.clearChat` with no confirmation. Add `.confirmationDialog` or `.alert` before destroying the session.

**Step 1: Add @State var showClearConfirmation = false**

**Step 2: Replace direct clearChat calls with showClearConfirmation = true**

**Step 3: Add .alert modifier**

```swift
.alert("Clear conversation?", isPresented: $showClearConfirmation) {
    Button("Clear", role: .destructive) { viewModel.clearChat(...) }
    Button("Cancel", role: .cancel) { }
} message: {
    Text("This will permanently delete all messages in this conversation.")
}
```

**Step 4: Build and commit**

---

### Task 5: Fix Agent `isCancelled` Not Resetting Between Runs

**Files:**
- Modify: `Sources/SBBender/Agent/Agent.swift:87` (top of `run()`)
- Test: `Tests/SBBenderTests/AgentTests.swift`

**Context:** `cancel()` sets `isCancelled = true`. If `run()` is called again without `reset()`, it immediately returns `.cancelled`. Fix: reset `isCancelled = false` at the start of every `run()`.

**Step 1: Write failing test**

```swift
@Test("Agent can run again after cancellation without reset")
func testRunAfterCancel() async throws {
    let agent = Agent(model: mockProvider)
    agent.cancel()
    let result = try await agent.run("Hello")
    #expect(result.status == .completed) // Currently fails: returns .cancelled
}
```

**Step 2: Add `isCancelled = false` at line 87** (start of the internal `run()` method)

**Step 3: Run tests, commit**

---

## Phase 2: Provider Reliability & Agent Loop Robustness

These fix reliability issues in the core agent loop and providers.

---

### Task 6: MLXProvider — Fix Multi-Turn Tool Call History

**Files:**
- Modify: `Sources/SBBender/Model/MLXProvider.swift:258-269` (toChatMessage for .assistant with tool calls)

**Context:** When an assistant message has tool calls, `toChatMessage` manually serializes them as `<tool_call>` XML and appends to text content. But the model's chat template already knows how to format assistant tool calls natively. The XML-in-text approach means in multi-turn the model sees malformed history.

**Fix:** For assistant messages with tool calls, emit the tool call info as part of the assistant message text but use the native format the model expects. Alternatively, since `Chat.Message` only takes a string `content` field, the XML format IS actually how Qwen3 represents tool calls in the chat template. Verify by checking what the Qwen3 chat template produces — if it matches the `<tool_call>` format, the current approach is correct. If not, adjust.

**Step 1: Verify with a test** — check that multi-turn (3+ iterations) works by running the existing `testDataAnalystMultiTurn` and confirming >2 tool calls work.

**Step 2: If malformed, adjust the format to match the model's native template output.**

---

### Task 7: FoundationProvider — Mark as Non-Agentic

**Files:**
- Modify: `Sources/SBBender/Model/FoundationProvider.swift`
- Modify: `Sources/SBBenderApp/Views/Components/ModelPickerViews.swift`

**Context:** FoundationProvider has no tool calling and no multi-turn. It should NOT be used as a fallback for agents. Either:
- Add a `supportsToolCalling: Bool` property to `ModelProvider` protocol
- Or add a warning in the UI when selecting Apple Intelligence: "Apple Intelligence does not support tool calling. Agent tools will not work."

**Step 1: Add `var supportsToolCalling: Bool { get }` to `ModelProvider` with default `true`**
**Step 2: Override to `false` in FoundationProvider**
**Step 3: Show warning badge in model picker when `supportsToolCalling == false`**
**Step 4: In Agent.run(), log a warning if the model doesn't support tool calling but tools are registered**

---

### Task 8: OpenAIProvider — Fix Streaming Tool Call Assembly

**Files:**
- Modify: `Sources/SBBender/Model/OpenAIProvider.swift:189-210`

**Context:** Tool calls in streaming are assembled into `pendingToolCalls` by index. They're only emitted when `finish_reason == "tool_calls"`. If the finish chunk has a different format or the finish reason string doesn't match exactly, tool calls are silently dropped.

**Fix:** Also emit pending tool calls when `finish_reason == "stop"` and `pendingToolCalls` is not empty. Also handle `finish_reason == "tool_calls"` AND `finish_reason == "tool_use"` (Anthropic-compatible endpoints use different strings).

---

### Task 9: Add `repeat_penalty` to OllamaProvider Streaming Options

**Files:**
- Modify: `Sources/SBBender/Model/OllamaProvider.swift:136-140`

**Context:** Non-streaming path has `"repeat_penalty": config.repetitionPenalty` in options. Streaming path is missing it. One-line fix.

---

## Phase 3: UX Polish & Missing Features

These improve the user experience from "functional" to "good."

---

### Task 10: Chat Session Management (Multiple Conversations)

**Files:**
- Modify: `Sources/SBBenderApp/ViewModels/AgentChatViewModel.swift`
- Modify: `Sources/SBBenderApp/Views/Agents/AgentChatView.swift`
- Modify: `Sources/SBBenderApp/Models/AgentConfig.swift`
- Modify: `Sources/SBBender/Storage/StorageBackend.swift` (add `getSessions(agentID:)`)

**Context:** Currently one session per agent. "New Chat" deletes the old one. Need:
- Store multiple sessions per agent (already supported by GRDB schema — sessions table has both `id` and `agent_id`)
- "New Chat" creates a new session, doesn't delete old
- Session list in the right panel or a dropdown
- Session titles auto-generated from first user message

---

### Task 11: Onboarding Flow

**Files:**
- Create: `Sources/SBBenderApp/Views/Onboarding/OnboardingView.swift`
- Modify: `Sources/SBBenderApp/SBBenderApp.swift`
- Modify: `Sources/SBBenderApp/Services/AppState.swift`

**Context:** First-launch experience:
1. Welcome screen explaining what SBBender does
2. Model download step — show recommended model for their hardware tier, download button with progress
3. Quick template selection — "Pick a starter agent" with 3-4 templates
4. Done — navigate to the agent chat

Store `hasCompletedOnboarding` in UserDefaults.

---

### Task 12: Human-Readable Tool/Skill Names

**Files:**
- Create: `Sources/SBBenderApp/Helpers/SkillMetadata.swift`
- Modify: `Sources/SBBenderApp/Views/Agents/AgentListView.swift` (agent cards)
- Modify: `Sources/SBBenderApp/Views/Agents/AgentBuilderSheet.swift` (template cards)
- Modify: `Sources/SBBenderApp/Views/Components/ActivityFeedView.swift`

**Context:** Raw skill IDs like `"entity-extraction"`, `"web-fetch"` shown to users everywhere. Create a metadata mapping:

```swift
static let metadata: [String: (name: String, icon: String, description: String)] = [
    "calendar": ("Calendar", "calendar", "Read and create calendar events"),
    "web-fetch": ("Web Browser", "globe", "Fetch and read web pages"),
    "shell": ("Terminal", "terminal", "Run shell commands"),
    "data-analysis": ("Data Analysis", "tablecells", "Analyze data with SQL"),
    // ...
]
```

Use this everywhere IDs are displayed.

---

### Task 13: Message Copy Button

**Files:**
- Modify: `Sources/SBBenderApp/Views/Components/ChatBubble.swift`

**Context:** No one-click copy. Add a copy button (appears on hover) that copies the message content to clipboard.

```swift
.overlay(alignment: .topTrailing) {
    if isHovered {
        Button { NSPasteboard.general.setString(message.content, forType: .string) }
        label: { Image(systemName: "doc.on.doc").font(.caption) }
        .buttonStyle(.plain)
    }
}
```

---

### Task 14: Send on Return, Newline on Shift+Return

**Files:**
- Modify: `Sources/SBBenderApp/Views/Agents/AgentChatView.swift` (input bar)

**Context:** Currently Command+Return to send. Normal chat apps use Return to send and Shift+Return for newline. Replace the TextEditor+Command shortcut pattern with an `onKeyPress` handler.

---

### Task 15: Model Download Progress

**Files:**
- Modify: `Sources/SBBenderApp/Views/Settings/ModelsSettingsView.swift`

**Context:** Download shows indeterminate spinner. MLX's `LLMModelFactory` reports progress via its download observer. Hook into that to show percentage + file size.

---

## Phase 4: Advanced Features & Architecture

These are significant features that make the framework competitive.

---

### Task 16: Structured Output Support

**Files:**
- Modify: `Sources/SBBender/Agent/Agent.swift`
- Modify: `Sources/SBBender/Agent/RunResult.swift`
- Modify: `Sources/SBBender/Model/ModelProvider.swift`

**Context:** Add `func run<T: Codable>(_ input: String, outputType: T.Type) -> RunResult<T>` that instructs the model to output JSON matching the schema and parses it.

---

### Task 17: Tool Confirmation Flow

**Files:**
- Modify: `Sources/SBBender/Agent/Agent.swift:256-314` (tool execution block)
- Add: `RunEvent.toolConfirmationRequired(name:arguments:)`

**Context:** `Tool.requiresConfirmation` is stored but never checked. When `requiresConfirmation == true`:
1. Emit `RunEvent.toolConfirmationRequired` with tool name + args
2. Pause execution (use a `CheckedContinuation`)
3. Expose `approveToolCall(id:)` / `rejectToolCall(id:)` on the agent
4. Resume or skip based on user decision

---

### Task 18: Token Budget Management

**Files:**
- Modify: `Sources/SBBender/Agent/ContextManager.swift`
- Modify: `Sources/SBBender/Agent/AgentConfiguration.swift`

**Context:** Add `maxContextTokens: Int?` to config. Before each model call, estimate total tokens in `runMessages`. If over budget, aggressively summarize or truncate older messages. Use the model's actual tokenizer if available (MLX exposes it via `ModelContext.tokenizer`).

---

### Task 19: Swarm Autonomous Mode — Tool-Based Delegation

**Files:**
- Modify: `Sources/SBBender/Swarm/Swarm.swift:141-181`
- Create: `Sources/SBBender/Swarm/DelegationTool.swift`

**Context:** Replace the brittle `DELEGATE:<member_id>:<instruction>` text parsing with a proper tool. Register a `delegate_to` tool on the leader agent that takes `(member_name: String, task: String)`. When the leader calls this tool, the swarm executes the member agent and returns the result.

---

### Task 20: Knowledge Persistence

**Files:**
- Modify: `Sources/SBBender/Knowledge/DocumentIndexer.swift`
- Modify: `Sources/SBBender/Storage/GRDBStorage.swift`

**Context:** HNSW graph and BM25 index are in-memory only. Add persistence to SQLite:
- Store embeddings + metadata in a `document_chunks` table
- Store HNSW graph edges in an `hnsw_edges` table
- Load on init, save after `buildIndex()`

---

### Task 21: Multi-Modal Tool Results

**Files:**
- Modify: `Sources/SBBender/Tool/Tool.swift` (change execute return type)
- Modify: `Sources/SBBender/Agent/Agent.swift` (handle rich tool results)

**Context:** Tools currently return `String`. Change to return `ToolResult` which can contain text, images, or structured data. This enables vision tools, chart tools, and screen capture to return actual images that the model can see in the next turn.

---

### Task 22: Retry & Fallback Provider Chain

**Files:**
- Create: `Sources/SBBender/Model/FallbackProvider.swift`

**Context:** A `FallbackProvider` wrapping an ordered list of providers. On failure or rate limit (HTTP 429), try the next provider. Configurable retry count and backoff.

---

### Task 23: Voice Input in Chat

**Files:**
- Modify: `Sources/SBBenderApp/Views/Agents/AgentChatView.swift` (input bar)
- Read: `Sources/SBBender/Skill/TranscriptionSkill.swift`

**Context:** TranscriptionSkill exists. Add a microphone button next to the send button. On press: start recording, on release: transcribe and insert text into the input field.

---

## Phase Summary

| Phase | Tasks | Impact | Effort |
|---|---|---|---|
| **Phase 1: Critical Blockers** | Tasks 1-5 | Users can actually use the app | 1-2 days |
| **Phase 2: Provider Reliability** | Tasks 6-9 | Agents work reliably across all providers | 1 day |
| **Phase 3: UX Polish** | Tasks 10-15 | App feels professional | 2-3 days |
| **Phase 4: Advanced Features** | Tasks 16-23 | Framework is competitive | 1-2 weeks |

## Verification

After each phase:
1. `swift build` — clean compile
2. `swift test` — all tests pass
3. Manual test with Qwen3-4B: create agent, chat, verify tools work
4. Manual test with Ollama (if available): same flow
