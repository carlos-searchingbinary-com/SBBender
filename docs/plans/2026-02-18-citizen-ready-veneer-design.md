# Citizen-Ready Friendly Veneer — Design Document

**Date:** 2026-02-18
**Target User:** Tech-curious adult (comfortable with Notion/Canva, knows what AI is, never configured a local model)
**Approach:** Friendly Veneer — translate internal concepts to user-facing labels, enforce guardrails, fix dead ends. No architecture changes.

---

## 1. Terminology Mapping

All user-facing strings are translated. Internal code names and property names stay unchanged.

| Internal Term | User-Facing Label | Affected Views |
|---|---|---|
| Agent | AI Assistant | Sidebar, headers, buttons, onboarding, builder, dashboard |
| Skills (native tools) | Capabilities | Builder Step 2, Dashboard, template cards |
| Skills (instruction/SKILL.md) | Behaviors | Builder skills section |
| MCP Servers | (hidden unless advanced) | Settings, Sidebar |
| Custom Tools | (hidden unless advanced) | Settings, Sidebar |
| Skill Lab | (hidden unless advanced) | Sidebar |
| Marketplace | Capability Store | Sidebar |
| Temperature | Creativity | Builder slider |
| Top P / Repetition Penalty | (hidden unless advanced) | Builder |
| Tool calls per turn / Max iterations | (hidden unless advanced) | Builder |
| Thinking | Deep Reasoning | Builder toggle |
| Learning | Memory | Builder toggle |

## 2. Onboarding Fixes

- Disable "Continue" on model step until selected model is downloaded
- Auto-start download on model selection
- Replace quantization pills: "4bit" → "Efficient", "8bit" → "High Quality"
- Replace parameter size pills: "4B" → "Small", "8B" → "Medium", "14B+" → "Large"
- Keep RAM badge as-is ("~8 GB")
- Hide HuggingFace repo paths — show only friendly name
- Resolve `skillIDs` to display names on template cards

## 3. Agent Builder Cleanup

- Temperature slider: "Creativity" with "Focused ← → Creative" labels
- Response length slider: "Concise ← → Detailed" labels
- Hide Top P, Repetition Penalty, Tool calls per turn, Max iterations behind advanced disclosure
- Wizard preview: replace raw values with friendly summaries
- "New Agent" → "New AI Assistant"

## 4. Settings Cleanup

- Gate MCP Servers tab behind `showAdvancedFeatures`
- Remove "Runtime: Swift 6.2" from About
- Rename "Tier: Medium" → human-readable hardware description
- Show friendly model name as primary, repo path as secondary in advanced mode only
- Rename "Storage" section → "Data"

## 5. Dashboard & Navigation Fixes

- "Needs Setup" cards → tappable, opens builder with that capability pre-enabled
- Sidebar: "My Agents" → "My Assistants", "Marketplace" → "Capability Store", section "Skills" → "Capabilities"
- Stats: "X assistants", "Active Capabilities"

## 6. Template Card Fixes

- Data Analysis template: update description to "Analyze CSV, Excel, and JSON data" (remove PostgreSQL/SQLite)
- All template cards: resolve `skillIDs` to display names via `SkillMetadata.displayName(for:)`

## 7. Error Message Improvements

- Wrap common errors with user-friendly messages + recovery hints
- Model load failure → "Couldn't load the AI model. Try restarting or downloading a different model."
- MCP failure → "A plugin connection failed. Your assistant will work without it."
- Knowledge failure → "Couldn't read that document. Try a different file format."
