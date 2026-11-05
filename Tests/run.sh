#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_binary="$(mktemp -t agentui-core-tests)"
store_binary="$(mktemp -t agentui-store-tests)"
conversation_binary="$(mktemp -t agentui-conversation-tests)"
remote_binary="$(mktemp -t agentui-remote-tests)"
claude_binary="$(mktemp -t agentui-claude-tests)"
swift_flags=(-parse-as-library -swift-version 6 -enable-upcoming-feature NonisolatedNonsendingByDefault
  -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature MemberImportVisibility)
trap 'rm -f "$test_binary" "$store_binary" "$conversation_binary" "$remote_binary" "$claude_binary"' EXIT
xcrun swiftc "${swift_flags[@]}" \
  AgentUI/Models/Workspace.swift AgentUI/Services/WorkspaceDisk.swift AgentUI/Models/TerminalLayout.swift AgentUI/Models/SidebarAppearance.swift AgentUI/Models/BridgeProtocol.swift AgentUI/Models/FloatingTerminal.swift \
  AgentUI/Services/GitService.swift AgentUI/Services/GitRepository.swift AgentUI/Models/DiscoveredWorktree.swift AgentUI/Models/RepositoryImport.swift AgentUI/Models/GitBranch.swift AgentUI/Models/WorktreeBranch.swift AgentUI/Models/BranchMergeState.swift AgentUI/Services/DefaultBranch.swift AgentUI/Services/AgentCLI.swift AgentUI/Services/BridgeMailbox.swift AgentUI/Services/FileSystemWatcher.swift \
  AgentUI/Models/InspectorModels.swift AgentUI/Models/GitAction.swift AgentUI/Models/GitChangeFolder.swift AgentUI/Models/RemoteWebAddress.swift AgentUI/Models/GitDiff.swift AgentUI/Services/ReadCommand.swift AgentUI/Services/CommandRunner.swift AgentUI/Services/GitConfiguration.swift AgentUI/Services/GitFilterGuard.swift AgentUI/Services/GitStatus.swift AgentUI/Services/GitRootCache.swift AgentUI/Services/GitBranchProtection.swift AgentUI/Services/BranchMergeCache.swift AgentUI/Services/FileEvents.swift AgentUI/Services/InspectorService.swift \
  AgentUI/Models/InspectorStore.swift AgentUI/Models/InspectorPreviews.swift AgentUI/Services/WorkspaceWriter.swift \
  AgentUI/Models/UsageModels.swift AgentUI/Models/UsageStore.swift AgentUI/Services/UsageService.swift \
  AgentUI/Models/AgentConversation.swift AgentUI/Models/AgentLaunch.swift AgentUI/Models/TerminalTheme.swift AgentUI/Models/Removal.swift AgentUI/Models/RemovalConfirmations.swift AgentUI/Models/TerminalAppearance.swift \
  AgentUI/Models/InstallationStatus.swift AgentUI/Platforms/macOS/TerminalKeyRoute.swift AgentUI/Services/AgentSkillInstaller.swift AgentUI/Services/CommandLineInstaller.swift AgentUI/Services/LoginShell.swift \
  AgentUI/Services/AgentProcess.swift AgentUI/Services/ConversationTranscripts.swift AgentUI/Models/AgentStatus.swift \
  AgentUI/Services/ClaudeSubagents.swift AgentUI/Models/Subagent.swift "AgentUI/Extensions/String+HomeAbbreviation.swift" \
  Tests/RegressionTests.swift Tests/RefreshTests.swift Tests/InspectorTests.swift Tests/UsageTests.swift Tests/SettingsTests.swift Tests/CoreTests.swift -o "$test_binary"
"$test_binary"

xcrun swiftc "${swift_flags[@]}" \
  AgentUI/Models/Workspace.swift AgentUI/Services/WorkspaceDisk.swift AgentUI/Models/TerminalLayout.swift AgentUI/Models/SidebarAppearance.swift AgentUI/Models/WorkspaceStore.swift AgentUI/Extensions/Array+Moving.swift AgentUI/Models/SidebarFilter.swift AgentUI/Models/Removal.swift AgentUI/Models/SidebarTerminalBlock.swift AgentUI/Models/WorkInProgress.swift AgentUI/Models/AgentStatus.swift \
  AgentUI/Models/AgentConversation.swift AgentUI/Models/Subagent.swift \
  AgentUI/Services/GitService.swift AgentUI/Services/GitRepository.swift AgentUI/Models/DiscoveredWorktree.swift AgentUI/Models/RepositoryImport.swift AgentUI/Models/GitBranch.swift AgentUI/Models/WorktreeBranch.swift AgentUI/Services/DefaultBranch.swift AgentUI/Services/GitBranchProtection.swift AgentUI/Services/TerminalSessionsDelegate.swift AgentUI/Services/WorkspaceWriter.swift \
  AgentUI/Services/ReadCommand.swift AgentUI/Services/CommandRunner.swift AgentUI/Services/GitConfiguration.swift AgentUI/Services/GitFilterGuard.swift \
  AgentUI/Models/InspectorModels.swift AgentUI/Models/GitAction.swift AgentUI/Models/RemoteWebAddress.swift AgentUI/Models/BranchMergeState.swift AgentUI/Models/GitDiff.swift \
  Tests/StoreTests.swift -o "$store_binary"
"$store_binary"

xcrun swiftc "${swift_flags[@]}" \
  AgentUI/Models/AgentConversation.swift AgentUI/Services/ConversationTranscripts.swift AgentUI/Services/ConversationIndex.swift AgentUI/Services/OpenCodeSessions.swift \
  AgentUI/Services/ReadCommand.swift AgentUI/Services/CommandRunner.swift AgentUI/Services/GitConfiguration.swift \
  Tests/ConversationTests.swift -o "$conversation_binary"
"$conversation_binary"


xcrun swiftc "${swift_flags[@]}" \
  AgentUI/Models/Workspace.swift AgentUI/Services/WorkspaceDisk.swift AgentUI/Models/TerminalLayout.swift AgentUI/Models/SidebarAppearance.swift AgentUI/Models/GitBranch.swift \
  AgentUI/Models/InspectorModels.swift AgentUI/Models/GitAction.swift AgentUI/Models/RemoteWebAddress.swift AgentUI/Models/BranchMergeState.swift AgentUI/Models/GitDiff.swift AgentUI/Models/AgentConversation.swift \
  AgentUI/Models/Data/RemoteProtocol.swift AgentUI/Models/Data/RemoteTerminalSnapshot.swift AgentUI/Models/Data/TerminalGridSize.swift AgentUI/Models/Data/SessionMessage.swift \
  AgentUI/Models/Data/RemoteGridRequests.swift "AgentUI/Extensions/Collection+TerminalFocusReport.swift" \
  AgentUI/Models/Data/PairingInvitation.swift AgentUI/Models/Data/SavedHost.swift AgentUI/Models/Data/LocalAddress.swift AgentUI/Core/Remote/QRCode.swift \
  AgentUI/Core/Session/SessionTranscript.swift \
  Tests/RemoteTests.swift -o "$remote_binary"
"$remote_binary"


xcrun swiftc "${swift_flags[@]}" \
  AgentUI/Models/Data/SessionMessage.swift AgentUI/Core/Session/SessionTranscript.swift \
  AgentUI/Core/Session/ChatMessageLog.swift AgentUI/Core/Session/ClaudeChatDecoder.swift AgentUI/Core/Session/CodexChatDecoder.swift \
  AgentUI/Core/Session/CopilotChatDecoder.swift AgentUI/Core/Session/ChatJournalReader.swift AgentUI/Services/FileSystemWatcher.swift \
  AgentUI/Platforms/macOS/AgentJournalMonitor.swift Tests/ChatJournalTests.swift -o "$claude_binary"
"$claude_binary"
