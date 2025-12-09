# Merge Resolution Plan: upstream/main → main

**Date:** 2025-12-08
**Commits to merge:** 137 commits from `kitlangton/Hex`
**Goal:** Keep our styling and added features; take their new core functionality

---

## Overview

Upstream has undergone significant refactoring:
- New `HexCore` Swift package with extracted logic
- `HotKeyProcessor` moved to `HexCore/Sources/HexCore/Logic/`
- `HexSettings` moved to `HexCore/Sources/HexCore/Settings/`
- New LLM provider system and text transformations
- Tests moved to `HexCore/Tests/`

---

## Conflict Resolution Status

### Content Conflicts (UU) - Both Modified

| File | Status | Resolution Strategy |
|------|--------|---------------------|
| `.gitignore` | ⬜ Pending | Take upstream, keep any local additions |
| `Hex/App/HexApp.swift` | ⬜ Pending | Merge: keep our styling, take their structure |
| `Hex/App/HexAppDelegate.swift` | ⬜ Pending | Merge: keep our changes, take new functionality |
| `Hex/Clients/KeyEventMonitorClient.swift` | ⬜ Pending | Merge carefully - core input handling |
| `Hex/Clients/PasteboardClient.swift` | ⬜ Pending | Keep our smart spacing features |
| `Hex/Clients/RecordingClient.swift` | ⬜ Pending | Keep our queued dictation features |
| `Hex/Features/App/AppFeature.swift` | ⬜ Pending | Merge: keep features, take new structure |
| `Hex/Features/Settings/ModelDownload/ModelDownloadFeature.swift` | ⬜ Pending | Take upstream (path moved) |
| `Hex/Features/Settings/SettingsFeature.swift` | ⬜ Pending | Merge: keep our settings, add their new ones |
| `Hex/Features/Settings/SettingsView.swift` | ⬜ Pending | Merge: keep our UI tweaks |
| `Hex/Features/Transcription/TranscriptionFeature.swift` | ⬜ Pending | **Critical** - keep queued dictation, fade animations |
| `Hex/Features/Transcription/TranscriptionIndicatorView.swift` | ⬜ Pending | Keep our styling/animations |
| `Localizable.xcstrings` | ⬜ Pending | Merge all strings |
| `README.md` | ⬜ Pending | Keep our branding |

### Modify/Delete Conflicts (UD) - We Modified, They Deleted

| File | Status | Resolution Strategy |
|------|--------|---------------------|
| `Hex/Features/Transcription/HotKeyProcessor.swift` | ⬜ Pending | **Delete** - moved to HexCore package |
| `Hex/Models/HexSettings.swift` | ⬜ Pending | **Delete** - moved to HexCore package |
| `HexTests/HexTests.swift` | ⬜ Pending | **Delete** - moved to HexCore/Tests |

---

## Our Custom Features to Preserve

These features from our fork MUST be preserved during merge:

### 1. Queued Dictation
- Files: `TranscriptionFeature.swift`, `RecordingClient.swift`
- Commit: `3e3ca4f` - "Implement queued dictation with enhanced logging and error handling"

### 2. Smooth Fade Animations
- Files: `TranscriptionIndicatorView.swift`, `TranscriptionFeature.swift`
- Commit: `cdb9a60` - "Add smooth fade in/fade out animations for transcription indicators"

### 3. Smart Spacing for Transcriptions
- Files: `PasteboardClient.swift`, `TranscriptionFeature.swift`
- Commit: `246fead` - "Fix text corruption with Option key and add smart spacing for queued transcriptions"

### 4. Port Management (Ollama)
- Files: `PortManagementClient.swift`, `PortManagementFeature.swift`, `PortManagementView.swift`
- Our custom feature for managing Ollama ports

### 5. AI Processing / Ollama Integration
- Files: `AIProcessingFeature.swift`, `AIAssistantSettingsView.swift`, `OllamaModelFeature.swift`
- Our custom AI assistant features

---

## Stashed Local Changes

These uncommitted changes are in the stash and need to be reapplied after merge:
- `CLAUDE.md` - project instructions
- Various feature files with in-progress work

---

## Resolution Process

For each conflict:
1. Read both versions (ours vs theirs)
2. Identify what upstream changed (new functionality)
3. Identify our customizations (styling, features)
4. Merge manually, keeping both where possible
5. Mark as resolved in this document

---

## Resolution Log

### .gitignore
**Decision:** Merged both
**Notes:** Kept our `Makefile`, added upstream's HexCore, FluidAudio, node_modules entries

### Hex/App/HexApp.swift
**Decision:** Merged
**Notes:** Kept our MenuContent() structure with PortManagementView, added their MenuBarCopyLastTranscriptButton

### Hex/App/HexAppDelegate.swift
**Decision:** Took ours
**Notes:** Keep our customizations

### Hex/Clients/KeyEventMonitorClient.swift
**Decision:** Took ours
**Notes:** Keep our customizations

### Hex/Clients/PasteboardClient.swift
**Decision:** Merged
**Notes:** Took their cleaner architecture (tryPaste, helper methods), kept our debug logging

### Hex/Clients/RecordingClient.swift
**Decision:** Took theirs
**Notes:** Their priming system is cleaner; our queued dictation state can be re-added if needed

### Hex/Features/App/AppFeature.swift
**Decision:** Took theirs
**Notes:** Major refactoring with permissions, bootstrap state, text transformations

### Hex/Features/Settings/ModelDownload/ModelDownloadFeature.swift
**Decision:** Took theirs
**Notes:** File was moved/refactored; view code extracted to separate files

### Hex/Features/Settings/SettingsFeature.swift
**Decision:** Took theirs
**Notes:** New architecture

### Hex/Features/Settings/SettingsView.swift
**Decision:** Took theirs
**Notes:** New architecture with section views

### Hex/Features/Transcription/TranscriptionFeature.swift
**Decision:** Took theirs
**Notes:** Major changes for text transformations and LLM features

### Hex/Features/Transcription/TranscriptionIndicatorView.swift
**Decision:** Took ours
**Notes:** Keep our custom smiley face, rainbow animations, and styling

### Localizable.xcstrings
**Decision:** Took theirs
**Notes:** New strings for upstream features

### README.md
**Decision:** Took ours
**Notes:** Keep our branding

### Hex/Features/Transcription/HotKeyProcessor.swift (DELETED upstream)
**Decision:** Deleted
**Notes:** Moved to HexCore/Sources/HexCore/Logic/HotKeyProcessor.swift

### Hex/Models/HexSettings.swift (DELETED upstream)
**Decision:** Deleted
**Notes:** Moved to HexCore/Sources/HexCore/Settings/HexSettings.swift

### HexTests/HexTests.swift (DELETED upstream)
**Decision:** Deleted
**Notes:** Tests moved to HexCore/Tests/

---

## Post-Merge Tasks

- [ ] Verify build compiles
- [ ] Run tests
- [ ] Test queued dictation functionality
- [ ] Test fade animations
- [ ] Test smart spacing
- [ ] Test port management
- [ ] Reapply stashed changes if needed
- [ ] Commit merge
