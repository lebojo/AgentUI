#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_binary="$(mktemp -t heka-core-tests)"
store_binary="$(mktemp -t heka-store-tests)"
conversation_binary="$(mktemp -t heka-conversation-tests)"
remote_binary="$(mktemp -t heka-remote-tests)"
claude_binary="$(mktemp -t heka-claude-tests)"
swift_flags=(-parse-as-library -swift-version 6 -enable-upcoming-feature NonisolatedNonsendingByDefault
  -enable-upcoming-feature InferIsolatedConformances -enable-upcoming-feature MemberImportVisibility)
trap 'rm -f "$test_binary" "$store_binary" "$conversation_binary" "$remote_binary" "$claude_binary"' EXIT
xcrun swiftc "${swift_flags[@]}" \
  Heka/Models/Workspace.swift Heka/Services/WorkspaceDisk.swift Heka/Models/TerminalLayout.swift Heka/Models/SidebarAppearance.swift Heka/Models/BridgeProtocol.swift Heka/Models/TerminalKey.swift Heka/Models/Data/SessionMessage.swift Heka/Models/FloatingTerminal.swift \
  Heka/Services/GitService.swift Heka/Services/GitRepository.swift Heka/Models/DiscoveredWorktree.swift Heka/Models/RepositoryImport.swift Heka/Models/GitBranch.swift Heka/Models/WorktreeBranch.swift Heka/Models/BranchMergeState.swift Heka/Services/DefaultBranch.swift Heka/Services/AgentCLI.swift Heka/Services/BridgeMailbox.swift Heka/Services/FileSystemWatcher.swift \
  Heka/Models/InspectorModels.swift Heka/Models/AgentPrompts.swift Heka/Models/AgentRequest.swift Heka/Models/GitAction.swift Heka/Models/GitChangeFolder.swift Heka/Models/RemoteWebAddress.swift "Heka/Extensions/String+QueryValue.swift" Heka/Models/GitDiff.swift Heka/Services/ReadCommand.swift Heka/Services/CommandRunner.swift Heka/Services/GitConfiguration.swift Heka/Services/GitFilterGuard.swift Heka/Services/GitStatus.swift Heka/Services/GitRootCache.swift Heka/Services/GitBranchProtection.swift Heka/Services/BranchMergeCache.swift Heka/Services/FileEvents.swift Heka/Services/InspectorService.swift \
  Heka/Models/InspectorStore.swift Heka/Models/GitActionQueue.swift Heka/Models/GitActionQueues.swift Heka/Models/InspectorPreviews.swift Heka/Services/WorkspaceWriter.swift \
  Heka/Models/UsageModels.swift Heka/Models/UsageStore.swift Heka/Services/UsageService.swift \
  Heka/Models/AgentConversation.swift Heka/Models/AgentLaunch.swift Heka/Models/TerminalTheme.swift Heka/Models/Removal.swift Heka/Models/RemovalConfirmations.swift Heka/Models/TerminalAppearance.swift \
  Heka/Models/InstallationStatus.swift Heka/Platforms/macOS/TerminalKeyRoute.swift Heka/Services/AgentSkillInstaller.swift Heka/Services/CommandLineInstaller.swift Heka/Services/LoginShell.swift \
  Heka/Services/AgentProcess.swift Heka/Services/ConversationTranscripts.swift Heka/Models/AgentStatus.swift \
  Heka/Services/ClaudeSubagents.swift Heka/Models/Subagent.swift "Heka/Extensions/String+HomeAbbreviation.swift" \
  Tests/RegressionTests.swift Tests/RefreshTests.swift Tests/InspectorTests.swift Tests/UsageTests.swift Tests/SettingsTests.swift Tests/CoreTests.swift -o "$test_binary"
"$test_binary"

xcrun swiftc "${swift_flags[@]}" \
  Heka/Models/Workspace.swift Heka/Services/WorkspaceDisk.swift Heka/Models/TerminalLayout.swift Heka/Models/SidebarAppearance.swift Heka/Models/WorkspaceStore.swift Heka/Extensions/Array+Moving.swift Heka/Models/SidebarFilter.swift Heka/Models/Removal.swift Heka/Models/SidebarTerminalBlock.swift Heka/Models/TerminalDragItem.swift Heka/Models/WorkInProgress.swift Heka/Models/AgentStatus.swift \
  Heka/Models/AgentConversation.swift Heka/Models/Subagent.swift \
  Heka/Services/GitService.swift Heka/Services/GitRepository.swift Heka/Models/DiscoveredWorktree.swift Heka/Models/RepositoryImport.swift Heka/Models/GitBranch.swift Heka/Models/WorktreeBranch.swift Heka/Services/DefaultBranch.swift Heka/Services/GitBranchProtection.swift Heka/Services/TerminalSessionsDelegate.swift Heka/Services/WorkspaceWriter.swift \
  Heka/Services/ReadCommand.swift Heka/Services/CommandRunner.swift Heka/Services/GitConfiguration.swift Heka/Services/GitFilterGuard.swift \
  Heka/Models/InspectorModels.swift Heka/Models/GitAction.swift Heka/Models/RemoteWebAddress.swift "Heka/Extensions/String+QueryValue.swift" Heka/Models/BranchMergeState.swift Heka/Models/GitDiff.swift \
  Tests/StoreTests.swift -o "$store_binary"
"$store_binary"

xcrun swiftc "${swift_flags[@]}" \
  Heka/Models/AgentConversation.swift Heka/Services/ConversationTranscripts.swift Heka/Services/ConversationIndex.swift Heka/Services/OpenCodeSessions.swift \
  Heka/Services/ReadCommand.swift Heka/Services/CommandRunner.swift Heka/Services/GitConfiguration.swift \
  Tests/ConversationTests.swift -o "$conversation_binary"
"$conversation_binary"


xcrun swiftc "${swift_flags[@]}" \
  Heka/Models/Workspace.swift Heka/Services/WorkspaceDisk.swift Heka/Models/TerminalLayout.swift Heka/Models/SidebarAppearance.swift Heka/Models/GitBranch.swift \
  Heka/Models/InspectorModels.swift Heka/Models/GitAction.swift Heka/Models/RemoteWebAddress.swift "Heka/Extensions/String+QueryValue.swift" Heka/Models/BranchMergeState.swift Heka/Models/GitDiff.swift Heka/Models/AgentConversation.swift \
  Heka/Models/Data/RemoteProtocol.swift Heka/Models/Data/RemoteTerminalSnapshot.swift Heka/Models/Data/TerminalGridSize.swift Heka/Models/Data/SessionMessage.swift \
  Heka/Models/Data/RemoteGridRequests.swift "Heka/Extensions/Collection+TerminalReport.swift" \
  Heka/Models/Data/PairingInvitation.swift Heka/Models/Data/SavedHost.swift Heka/Models/Data/LocalAddress.swift Heka/Core/Remote/QRCode.swift \
  Heka/Core/Session/SessionTranscript.swift \
  Tests/RemoteTests.swift -o "$remote_binary"
"$remote_binary"


xcrun swiftc "${swift_flags[@]}" \
  Heka/Models/Data/SessionMessage.swift Heka/Core/Session/SessionTranscript.swift \
  Heka/Core/Session/ChatMessageLog.swift Heka/Core/Session/ClaudeChatDecoder.swift Heka/Core/Session/CodexChatDecoder.swift \
  Heka/Core/Session/CopilotChatDecoder.swift Heka/Core/Session/ChatJournalReader.swift Heka/Services/FileSystemWatcher.swift \
  Heka/Platforms/macOS/AgentJournalMonitor.swift Tests/ChatJournalTests.swift -o "$claude_binary"
"$claude_binary"
