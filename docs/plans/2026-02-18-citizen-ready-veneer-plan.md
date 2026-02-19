# Citizen-Ready Friendly Veneer — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make SBBender's UI citizen-ready for tech-curious adults by translating developer terminology, enforcing guardrails, and fixing dead ends — all UI-layer changes only.

**Architecture:** Pure SwiftUI view modifications. No protocol, model, or framework changes. All renames are display-only — internal property names, config keys, and persistence schemas stay unchanged. The plan touches 10 files across the SBBenderApp target.

**Tech Stack:** SwiftUI, SBBender framework (read-only), existing `SkillMetadata` helper for skill ID → display name resolution.

---

### Task 1: Rename Sidebar Terminology

**Files:**
- Modify: `Sources/SBBenderApp/Views/SidebarView.swift:12-64`

**Step 1: Apply renames**

Change these specific strings in `SidebarView.swift`:

| Line | Old | New |
|------|-----|-----|
| 14 | `Label("Dashboard", ...)` | (keep as-is) |
| 15 | `Section("Agents")` | `Section("AI Assistants")` |
| 16 | `Label("My Agents", ...)` | `Label("My Assistants", ...)` |
| 38 | `Section("Teams")` | (keep as-is) |
| 42 | `Section("Skills")` | `Section("Capabilities")` |
| 43 | `Label("Marketplace", ...)` | `Label("Capability Store", ...)` |
| 64 | `.navigationTitle("SBBender")` | (keep as-is) |

The exact edits:

```swift
// Line 15: Section("Agents") → Section("AI Assistants")
Section("AI Assistants") {

// Line 16: Label("My Agents", ...) → Label("My Assistants", ...)
Label("My Assistants", systemImage: "brain.head.profile")

// Line 42: Section("Skills") → Section("Capabilities")
Section("Capabilities") {

// Line 43: Label("Marketplace", ...) → Label("Capability Store", ...)
Label("Capability Store", systemImage: "storefront")
```

**Step 2: Build to verify**

Run: `swift build --product SBBenderApp 2>&1 | tail -5`
Expected: Build succeeded (no API changes, just string literals)

**Step 3: Commit**

```bash
git add Sources/SBBenderApp/Views/SidebarView.swift
git commit -m "ui: rename sidebar labels for citizen-readiness"
```

---

### Task 2: Rename AgentListView Terminology + Fix Template Skill IDs

**Files:**
- Modify: `Sources/SBBenderApp/Views/Agents/AgentListView.swift:83-84,116,206-209,294,303,309,509-516`

**Step 1: Fix "New Agent" button**

Line 83-84: Change the button label text:
```swift
// Old:
Text("New Agent")
// New:
Text("New AI Assistant")
```

**Step 2: Fix navigation title**

Line 116:
```swift
// Old:
.navigationTitle("My Agents")
// New:
.navigationTitle("My Assistants")
```

**Step 3: Fix empty state text**

Lines 206-209:
```swift
// Old:
Text("Create your first agent")
// ...
Text("Pick a template to get started, or build one from scratch")
// New:
Text("Create your first AI assistant")
// ...
Text("Pick a template to get started, or build one from scratch")
```

**Step 4: Rename feature pills in AgentCard**

Line 294: `"\(config.attachedSkillIDs.count) Skills"` → `"\(config.attachedSkillIDs.count) Behaviors"`

Line 303: `"\(config.mcpServerIDs.count) MCP"` → `"\(config.mcpServerIDs.count) Plugins"` (only shows when advanced features enabled, but cleaner label)

Line 309: `"Thinking"` → `"Deep Reasoning"`

**Step 5: Fix LargeTemplateCard skill IDs → display names**

Lines 509-516 in `LargeTemplateCard`. Replace raw `skillID` with resolved display name:

```swift
// Old (line 510):
Text(skillID)
// New:
Text(SkillMetadata.displayName(for: skillID))
```

This requires adding `import` — but `SkillMetadata` is already in the same module (SBBenderApp), no import needed.

**Step 6: Build to verify**

Run: `swift build --product SBBenderApp 2>&1 | tail -5`
Expected: Build succeeded

**Step 7: Commit**

```bash
git add Sources/SBBenderApp/Views/Agents/AgentListView.swift
git commit -m "ui: rename agent list labels and resolve template skill IDs"
```

---

### Task 3: Rename AgentBuilderSheet Terminology

**Files:**
- Modify: `Sources/SBBenderApp/Views/Agents/AgentBuilderSheet.swift:6-26,38,173,178,180,190,208,273,406,581,899,911,942-959,1021`

**Step 1: Rename builder step titles**

Lines 11-16, the `BuilderStep.title` computed property:
```swift
// Old:
case .persona: "Persona"
case .capabilities: "Capabilities"
case .behavior: "Behavior"
// New:
case .persona: "Personality"
case .capabilities: "Capabilities"
case .behavior: "Settings"
```

**Step 2: Fix default name**

Line 38:
```swift
// Old:
@State private var name: String = "New Agent"
// New:
@State private var name: String = "New AI Assistant"
```

**Step 3: Fix header fallback name**

Line 173:
```swift
// Old:
Text(name.isEmpty ? "Untitled Agent" : name)
// New:
Text(name.isEmpty ? "Untitled Assistant" : name)
```

**Step 4: Rename header summary labels**

Line 178: `"\(enabledNativeToolIDs.count) tools"` → `"\(enabledNativeToolIDs.count) capabilities"`
Line 180: `"\(attachedSkillIDs.count) skills"` → `"\(attachedSkillIDs.count) behaviors"`
Line 190: `"\(mcpServerIDs.count) MCP"` → `"\(mcpServerIDs.count) plugins"`

**Step 5: Rename AI Setup help text**

Line 208:
```swift
// Old:
.help("Describe what you want and let AI configure the agent")
// New:
.help("Describe what you want and let AI configure the assistant")
```

**Step 6: Fix edit mode name field placeholder**

Line 273:
```swift
// Old:
TextField("Give your agent a name", text: $name)
// New:
TextField("Give your assistant a name", text: $name)
```

**Step 7: Fix persona step name field placeholder**

Line 406:
```swift
// Old:
TextField("Give your agent a name", text: $name)
// New:
TextField("Give your assistant a name", text: $name)
```

**Step 8: Fix instructions helper text**

Line 581:
```swift
// Old:
Text("Tell the agent who it is and how it should behave — supports Markdown")
// New:
Text("Tell the assistant who it is and how it should behave — supports Markdown")
```

**Step 9: Rename "Native Tools" section header**

Line 899:
```swift
// Old:
Text("Native Tools")
// New:
Text("Capabilities")
```

Line 911:
```swift
// Old:
Text("Built-in Apple capabilities your agent can use as tools")
// New:
Text("Built-in Apple capabilities your assistant can use")
```

**Step 10: Rename "Skills" section to "Behaviors"**

Line 945:
```swift
// Old:
Text("Skills")
// New:
Text("Behaviors")
```

Line 959:
```swift
// Old:
Text("Instruction skills that shape how your agent thinks and works")
// New:
Text("Instruction behaviors that shape how your assistant thinks and works")
```

Line 967:
```swift
// Old:
Text("No skills installed — visit the Skill Library to add some")
// New:
Text("No behaviors installed — visit the Capability Store to add some")
```

**Step 11: Rename "Create Agent" button**

Line 1021:
```swift
// Old:
Button("Create Agent") { save() }
// New:
Button("Create Assistant") { save() }
```

**Step 12: Rename knowledge subtitle in features**

Line 296 and 796:
```swift
// Old:
subtitle: "Feed documents and files for the agent to reference",
// New:
subtitle: "Feed documents and files for the assistant to reference",
```

**Step 13: Build to verify**

Run: `swift build --product SBBenderApp 2>&1 | tail -5`
Expected: Build succeeded

**Step 14: Commit**

```bash
git add Sources/SBBenderApp/Views/Agents/AgentBuilderSheet.swift
git commit -m "ui: rename builder labels for citizen-readiness"
```

---

### Task 4: Fix AgentWizardSheet Preview

**Files:**
- Modify: `Sources/SBBenderApp/Views/Agents/AgentWizardSheet.swift:24-25,49,65,88-101`

**Step 1: Rename header**

Line 24: `"AI Agent Wizard"` → `"AI Assistant Wizard"`
Line 25: `"Describe your ideal agent and let AI configure it"` → `"Describe your ideal assistant and let AI configure it"`

**Step 2: Rename example text**

Line 49: `"An agent that helps me..."` → `"An assistant that helps me manage my calendar, search the web for meeting prep, and summarize discussions"`

**Step 3: Rename button text**

Line 65: `"Generate Agent Config"` → `"Generate Configuration"`

**Step 4: Replace raw preview rows with friendly labels**

Lines 92-101. Replace the preview block:

```swift
// Old:
previewRow("Name", preview.name)
previewRow("Emoji", preview.emoji)
previewRow("Tools", preview.enabledSkillIDs.joined(separator: ", "))
previewRow("Skills", preview.attachedSkillIDs.joined(separator: ", "))
previewRow("Temperature", String(format: "%.2f", preview.temperature))
previewRow("Thinking", preview.enableThinking ? "Enabled" : "Disabled")
previewRow("Knowledge", preview.knowledgeEnabled ? "Enabled" : "Disabled")
previewRow("Learning", preview.learningEnabled ? "Enabled" : "Disabled")

// New:
previewRow("Name", preview.name)
previewRow("Emoji", preview.emoji)
previewRow("Capabilities", preview.enabledSkillIDs.map { SkillMetadata.displayName(for: $0) }.joined(separator: ", "))
if !preview.attachedSkillIDs.isEmpty {
    previewRow("Behaviors", preview.attachedSkillIDs.joined(separator: ", "))
}
previewRow("Creativity", friendlyTemperature(preview.temperature))
previewRow("Deep Reasoning", preview.enableThinking ? "On" : "Off")
previewRow("Knowledge Base", preview.knowledgeEnabled ? "On" : "Off")
previewRow("Memory", preview.learningEnabled ? "On" : "Off")
```

Add helper function at the bottom of the file (before the closing brace):

```swift
private func friendlyTemperature(_ t: Float) -> String {
    switch t {
    case 0.0...0.2: return "Very precise"
    case 0.2...0.5: return "Focused"
    case 0.5...0.8: return "Balanced"
    case 0.8...1.1: return "Creative"
    default: return "Very creative"
    }
}
```

**Step 5: Build to verify**

Run: `swift build --product SBBenderApp 2>&1 | tail -5`
Expected: Build succeeded

**Step 6: Commit**

```bash
git add Sources/SBBenderApp/Views/Agents/AgentWizardSheet.swift
git commit -m "ui: friendly wizard preview with resolved skill names"
```

---

### Task 5: Onboarding — Enforce Model Download + Friendly Labels

**Files:**
- Modify: `Sources/SBBenderApp/Views/Onboarding/OnboardingView.swift:86-93,145-163,200-221,336,402-413`

**Step 1: Update welcome text**

Line 86-89:
```swift
// Old:
Text("Welcome to SBBender")
// ...
Text("Build AI agents that run on your Mac using local models.\nNo cloud, no API keys, full privacy.")
// New:
Text("Welcome to SBBender")
// ...
Text("Run AI assistants on your Mac using local models.\nNo cloud, no API keys, full privacy.")
```

**Step 2: Add computed property for model downloaded check**

Add this computed property inside `OnboardingView` (after the state vars around line 13):

```swift
private var isSelectedModelReady: Bool {
    guard let id = selectedModelID else { return false }
    return appState.modelRegistry.isMLXModelDownloaded(id)
        || appState.modelRegistry.mlxDownloadState[id] == .completed
}
```

**Step 3: Auto-start download on model selection**

Add an `.onChange(of: selectedModelID)` modifier to the model step view (after the `.task` on line 46):

```swift
.onChange(of: selectedModelID) { _, newID in
    guard let id = newID,
          !appState.modelRegistry.isMLXModelDownloaded(id),
          appState.modelRegistry.mlxDownloadState[id] == nil || appState.modelRegistry.mlxDownloadState[id] == .idle
    else { return }
    Task { await appState.modelRegistry.downloadMLXModel(id: id) }
}
```

**Step 4: Disable "Continue" on model step until downloaded**

Lines 407-410, the Continue button:
```swift
// Old:
Button("Continue") {
    withAnimation { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .templates }
}
.buttonStyle(.borderedProminent)
.controlSize(.large)

// New:
Button("Continue") {
    withAnimation { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .templates }
}
.buttonStyle(.borderedProminent)
.controlSize(.large)
.disabled(step == .model && !isSelectedModelReady)
```

Add helper text below the button when on model step (inside the `else` block after the button):

```swift
if step == .model && !isSelectedModelReady {
    Text("Download a model to continue")
        .font(.caption)
        .foregroundStyle(.orange)
}
```

**Step 5: Replace quantization pills with friendly labels**

Lines 207-221 in `modelCard(_:)`. Replace the three pill badges:

```swift
// Old:
Text(model.parameterSize)
    // ... blue pill
Text(model.quantization)
    // ... purple pill
Text("~\(model.ramRequired) GB")
    // ... orange pill

// New:
Text(friendlySize(model.parameterSize))
    .font(.system(size: 9, weight: .medium))
    .padding(.horizontal, 5)
    .padding(.vertical, 1)
    .background(Capsule().fill(.blue.opacity(0.08)))
    .foregroundStyle(.blue)

Text(friendlyQuantization(model.quantization))
    .font(.system(size: 9, weight: .medium))
    .padding(.horizontal, 5)
    .padding(.vertical, 1)
    .background(Capsule().fill(.green.opacity(0.08)))
    .foregroundStyle(.green)

Text("~\(model.ramRequired) GB")
    .font(.system(size: 9, weight: .medium))
    .padding(.horizontal, 5)
    .padding(.vertical, 1)
    .background(Capsule().fill(.orange.opacity(0.08)))
    .foregroundStyle(.orange)
```

Add helper functions:

```swift
private func friendlySize(_ size: String) -> String {
    let s = size.lowercased().replacingOccurrences(of: "b", with: "")
    guard let num = Float(s) else { return size }
    if num <= 4 { return "Small" }
    if num <= 8 { return "Medium" }
    return "Large"
}

private func friendlyQuantization(_ q: String) -> String {
    if q.lowercased().contains("4bit") || q.lowercased().contains("4-bit") { return "Efficient" }
    if q.lowercased().contains("8bit") || q.lowercased().contains("8-bit") { return "High Quality" }
    return q
}
```

**Step 6: Resolve template skill IDs in template cards**

Line 336 — in `templateCard`, the skill preview section shows raw IDs. Change:
```swift
// Old:
Text("\(template.skillIDs.count) skills")
// New:
Text("\(template.skillIDs.count) capabilities")
```

Also in the onboarding `templateCard`, the skillIDs are shown as a count only (not raw), so this is mainly the label change.

**Step 7: Build to verify**

Run: `swift build --product SBBenderApp 2>&1 | tail -5`
Expected: Build succeeded

**Step 8: Commit**

```bash
git add Sources/SBBenderApp/Views/Onboarding/OnboardingView.swift
git commit -m "ui: enforce model download in onboarding + friendly labels"
```

---

### Task 6: Settings Cleanup — Gate MCP Tab + Clean About

**Files:**
- Modify: `Sources/SBBenderApp/Views/Settings/SettingsView.swift:1-100`

**Step 1: Gate MCP tab behind advanced features**

The `SettingsTab` enum needs dynamic filtering. Replace the picker content to filter out MCP when not advanced:

```swift
// Replace body (lines 14-38) with:
var body: some View {
    VStack(spacing: 0) {
        Picker("Settings", selection: $selectedTab) {
            ForEach(visibleTabs, id: \.self) { tab in
                Text(tab.displayName).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)

        switch selectedTab {
        case .models:
            ModelsSettingsView()
                .environment(appState)
        case .mcpServers:
            MCPSettingsView()
                .environment(appState)
        case .general:
            GeneralSettingsContent()
                .environment(appState)
        }
    }
    .navigationTitle("Settings")
}

private var visibleTabs: [SettingsTab] {
    if appState.showAdvancedFeatures {
        return SettingsTab.allCases
    } else {
        return SettingsTab.allCases.filter { $0 != .mcpServers }
    }
}
```

Add `displayName` to the enum:
```swift
enum SettingsTab: String, CaseIterable {
    case models = "Models"
    case mcpServers = "MCP Servers"
    case general = "General"

    var displayName: String { rawValue }
}
```

Also reset selectedTab if MCP is hidden and was selected:
```swift
.onChange(of: appState.showAdvancedFeatures) { _, newValue in
    if !newValue && selectedTab == .mcpServers {
        selectedTab = .models
    }
}
```

**Step 2: Clean up General settings About section**

Lines 80-86, replace the About section:

```swift
// Old:
Section("About") {
    LabeledContent("App", value: "SBBender")
    LabeledContent("Runtime", value: "Swift 6.2")
    LabeledContent("Platform", value: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    LabeledContent("Hardware", value: appState.hardwareInfo.chipName)
    LabeledContent("Tier", value: appState.hardwareInfo.modelTier.displayName)
}

// New:
Section("About") {
    LabeledContent("App", value: "SBBender")
    LabeledContent("Platform", value: "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    LabeledContent("Hardware", value: "\(appState.hardwareInfo.chipName) — \(appState.hardwareInfo.totalRAMGB) GB")
}
```

**Step 3: Rename "Storage" section to "Data"**

Line 58:
```swift
// Old:
Section("Storage") {
// New:
Section("Data") {
```

Remove "Custom Tools" and "MCP Servers" counts from non-advanced mode:
```swift
Section("Data") {
    LabeledContent("Assistants", value: "\(appState.agents.count)")
    LabeledContent("Teams", value: "\(appState.teams.count)")
    if appState.showAdvancedFeatures {
        LabeledContent("Custom Tools", value: "\(appState.toolConfigs.count)")
        LabeledContent("MCP Servers", value: "\(appState.mcpServerConfigs.count)")
    }
    // ... Clear All Data button stays
}
```

**Step 4: Build to verify**

Run: `swift build --product SBBenderApp 2>&1 | tail -5`
Expected: Build succeeded

**Step 5: Commit**

```bash
git add Sources/SBBenderApp/Views/Settings/SettingsView.swift
git commit -m "ui: gate MCP settings tab and clean About section"
```

---

### Task 7: ModelsSettingsView — Hide Repo Paths for Non-Advanced

**Files:**
- Modify: `Sources/SBBenderApp/Views/Settings/ModelsSettingsView.swift:285-304`

**Step 1: Conditionally show repo path in downloaded model row**

Lines 285-304. The `downloadedModelRow` shows the full `modelID` (e.g., "mlx-community/Qwen3-4B-4bit") as subtitle. Gate it:

```swift
private func downloadedModelRow(_ modelID: String) -> some View {
    let shortName = modelID.components(separatedBy: "/").last ?? modelID
    return HStack {
        Image(systemName: "cpu")
            .foregroundStyle(.green)
            .font(.caption)
        VStack(alignment: .leading, spacing: 1) {
            Text(shortName)
                .font(.body.weight(.medium))
            if appState.showAdvancedFeatures {
                Text(modelID)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        Spacer()
        Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .font(.caption)
    }
    .padding(.vertical, 4)
}
```

**Step 2: Build to verify**

Run: `swift build --product SBBenderApp 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add Sources/SBBenderApp/Views/Settings/ModelsSettingsView.swift
git commit -m "ui: hide model repo paths unless advanced mode"
```

---

### Task 8: Dashboard — Fix Dead Ends + Rename Labels

**Files:**
- Modify: `Sources/SBBenderApp/Views/Dashboard/DashboardView.swift:29-35,57-112,118-119,129`

**Step 1: Update hero text**

Lines 29-35:
```swift
// Old:
Text("Your AI Can...")
// ...
Text("These are the capabilities available to your agents — powered by Apple Silicon and local models.")

// New:
Text("Your AI Can...")
// ...
Text("These are the capabilities available to your assistants — powered by Apple Silicon and local models.")
```

**Step 2: Fix "Needs Setup" to navigate to builder**

Lines 57-62 in `capabilityCard`. Replace the button action:

```swift
// Old:
Button {
    if let agentID = cap.availableInAgentID {
        appState.selectedSidebarItem = .agentChat(agentID)
    }
} label: {

// New:
Button {
    if let agentID = cap.availableInAgentID {
        appState.selectedSidebarItem = .agentChat(agentID)
    } else {
        // "Needs Setup" → navigate to agent list so user can create one
        appState.selectedSidebarItem = .agents
    }
} label: {
```

**Step 3: Update "Needs Setup" badge text**

Line 73:
```swift
// Old:
Text(cap.isActive ? "Active" : "Needs Setup")
// New:
Text(cap.isActive ? "Active" : "Add to Assistant")
```

**Step 4: Rename stats footer**

Line 118:
```swift
// Old:
statBadge(value: "\(appState.agents.count)", label: "Agents")
// New:
statBadge(value: "\(appState.agents.count)", label: "Assistants")
```

Line 119:
```swift
// Old:
statBadge(value: "\(activeSkillCount)", label: "Active Skills")
// New:
statBadge(value: "\(activeSkillCount)", label: "Active Capabilities")
```

**Step 5: Build to verify**

Run: `swift build --product SBBenderApp 2>&1 | tail -5`
Expected: Build succeeded

**Step 6: Commit**

```bash
git add Sources/SBBenderApp/Views/Dashboard/DashboardView.swift
git commit -m "ui: fix dashboard dead ends and rename labels"
```

---

### Task 9: Fix Agent Templates JSON

**Files:**
- Modify: `registry/agent-templates.json`

**Step 1: Update Data Analyst description**

The current description at line 59 is:
```json
"description": "Analyze CSV, Excel exports, and text data with shell tools"
```

This is actually already good (no PostgreSQL/SQLite mention). However, the instructions at line 61 mention `DuckDB` implicitly through `analyzeData` — that's fine since it's a system prompt the user won't see directly.

Check: the Dashboard `buildCapabilities()` already says "Query and analyze CSV/Excel data" — correct.

No change needed for the description. But verify: is there a reference to PostgreSQL or SQLite elsewhere in the templates? Looking at the full JSON... no. The Data Analyst template description is already clean.

**Skip this task — the template JSON is already citizen-friendly.** Move on.

**Step 2: Commit**

No commit needed.

---

### Task 10: Improve Error Toast Messages

**Files:**
- Modify: `Sources/SBBenderApp/Services/AppState.swift` (error toast sites)

**Step 1: Find and wrap error toast calls**

Search for `addToast(.init(severity: .error` in AppState.swift. The toast system is already in place. We need to ensure the messages are user-friendly.

Use `Grep` to find all `addToast` calls in AppState:

Run: `grep -n "addToast" Sources/SBBenderApp/Services/AppState.swift`

For each error toast, ensure the message has:
1. A plain-English title (no technical jargon)
2. A recovery hint in the `message` field

Common patterns to fix:

```swift
// Model load failures:
// Old: addToast(.init(severity: .error, title: "Model load failed", message: error.localizedDescription))
// New: addToast(.init(severity: .error, title: "Couldn't load the AI model", message: "Try restarting the app or downloading a different model in Settings."))

// MCP failures:
// Old: addToast(.init(severity: .error, title: "MCP connection failed", message: error.localizedDescription))
// New: addToast(.init(severity: .error, title: "A plugin connection failed", message: "Your assistant will work without it. Check Settings to reconnect."))

// Knowledge ingest failures:
// Old: addToast(.init(severity: .error, title: "Knowledge ingest failed", message: error.localizedDescription))
// New: addToast(.init(severity: .error, title: "Couldn't read that document", message: "Try a different file format (PDF, TXT, or Markdown)."))
```

**Note:** This step requires reading AppState.swift first to find exact toast call sites. The implementer should `grep -n "addToast" Sources/SBBenderApp/Services/AppState.swift` and update each call with a friendly message + recovery hint. Keep the `os_log` calls with technical details for debugging.

**Step 2: Build to verify**

Run: `swift build --product SBBenderApp 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Commit**

```bash
git add Sources/SBBenderApp/Services/AppState.swift
git commit -m "ui: friendlier error toast messages with recovery hints"
```

---

### Task 11: Final Verification

**Step 1: Run core tests**

Run: `swift test --filter SBBenderCoreTests 2>&1 | tail -10`
Expected: 142 tests passed (no behavior changes, only UI strings)

**Step 2: Build release**

Run: `swift build -c release --product SBBenderApp 2>&1 | tail -5`
Expected: Build succeeded

**Step 3: Manual smoke test checklist**

Launch the app and verify:
- [ ] Sidebar says "AI Assistants", "My Assistants", "Capabilities", "Capability Store"
- [ ] Dashboard says "Assistants" and "Active Capabilities" in footer
- [ ] Dashboard "Add to Assistant" cards navigate to agent list
- [ ] Agent builder says "New AI Assistant", "Create Assistant"
- [ ] Builder labels: "Capabilities" (not "Native Tools"), "Behaviors" (not "Skills")
- [ ] Settings: MCP tab hidden when Advanced off
- [ ] Settings About: no "Runtime: Swift 6.2", no raw "Tier"
- [ ] Onboarding: model step blocks Continue until download completes
- [ ] Onboarding: quantization shows "Efficient"/"High Quality" not "4bit"/"8bit"
- [ ] Template cards show "Web Fetch" not "web-fetch"
- [ ] Wizard preview shows "Creativity: Balanced" not "Temperature: 0.70"

**Step 4: Final commit (if any fixups needed)**

```bash
git add -A
git commit -m "ui: citizen-ready veneer — final fixups"
```
