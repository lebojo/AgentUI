#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_binary="$(mktemp -t agentui-core-tests)"
store_binary="$(mktemp -t agentui-store-tests)"
conversation_binary="$(mktemp -t agentui-conversation-tests)"
swift_flags=(-parse-as-library -swift-version 6 -enable-upcoming-feature NonisolatedNonsendingByDefault
  -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature MemberImportVisibility)
trap 'rm -f "$test_binary" "$store_binary" "$conversation_binary"' EXIT
xcrun swiftc "${swift_flags[@]}" \
  AgentUI/Models/Workspace.swift AgentUI/Models/TerminalLayout.swift AgentUI/Models/SidebarAppearance.swift AgentUI/Models/BridgeProtocol.swift \
  AgentUI/Services/GitService.swift AgentUI/Services/GitRepository.swift AgentUI/Services/AgentCLI.swift AgentUI/Services/BridgeMailbox.swift AgentUI/Services/DirectoryWatcher.swift \
  AgentUI/Models/InspectorModels.swift AgentUI/Models/GitDiff.swift AgentUI/Services/ReadCommand.swift AgentUI/Services/CommandRunner.swift AgentUI/Services/GitConfiguration.swift AgentUI/Services/GitFilterGuard.swift AgentUI/Services/FileEvents.swift AgentUI/Services/InspectorService.swift \
  AgentUI/Models/InspectorStore.swift AgentUI/Models/InspectorPreviews.swift AgentUI/Services/WorkspaceWriter.swift \
  AgentUI/Models/UsageModels.swift AgentUI/Models/UsageStore.swift AgentUI/Services/UsageService.swift \
  AgentUI/Models/AgentConversation.swift AgentUI/Models/AgentLaunch.swift AgentUI/Models/TerminalTheme.swift AgentUI/Models/TerminalAppearance.swift \
  AgentUI/Services/AgentProcess.swift AgentUI/Services/ConversationTranscripts.swift \
  Tests/RegressionTests.swift Tests/RefreshTests.swift Tests/InspectorTests.swift Tests/UsageTests.swift Tests/SettingsTests.swift Tests/CoreTests.swift -o "$test_binary"
"$test_binary"

xcrun swiftc "${swift_flags[@]}" \
  AgentUI/Models/Workspace.swift AgentUI/Models/TerminalLayout.swift AgentUI/Models/SidebarAppearance.swift AgentUI/Models/WorkspaceStore.swift AgentUI/Models/SidebarFilter.swift \
  AgentUI/Models/AgentConversation.swift \
  AgentUI/Services/GitService.swift AgentUI/Services/GitRepository.swift AgentUI/Services/WorkspaceWriter.swift \
  AgentUI/Services/ReadCommand.swift AgentUI/Services/CommandRunner.swift AgentUI/Services/GitConfiguration.swift \
  Tests/StoreTests.swift -o "$store_binary"
"$store_binary"

xcrun swiftc "${swift_flags[@]}" \
  AgentUI/Models/AgentConversation.swift AgentUI/Services/ConversationTranscripts.swift AgentUI/Services/ConversationIndex.swift AgentUI/Services/OpenCodeSessions.swift \
  AgentUI/Services/ReadCommand.swift AgentUI/Services/CommandRunner.swift AgentUI/Services/GitConfiguration.swift \
  Tests/ConversationTests.swift -o "$conversation_binary"
"$conversation_binary"
