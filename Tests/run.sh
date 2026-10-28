#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_binary="$(mktemp -t agentui-core-tests)"
store_binary="$(mktemp -t agentui-store-tests)"
trap 'rm -f "$test_binary" "$store_binary"' EXIT
xcrun swiftc -parse-as-library \
  AgentUI/Models/Workspace.swift AgentUI/Models/BridgeProtocol.swift \
  AgentUI/Services/GitService.swift AgentUI/Services/GitRepository.swift AgentUI/Services/AgentCLI.swift \
  AgentUI/Models/InspectorModels.swift AgentUI/Services/ReadCommand.swift AgentUI/Services/CommandRunner.swift AgentUI/Services/InspectorService.swift \
  AgentUI/Models/InspectorStore.swift AgentUI/Services/WorkspaceWriter.swift \
  Tests/RegressionTests.swift Tests/InspectorTests.swift Tests/CoreTests.swift -o "$test_binary"
"$test_binary"

xcrun swiftc -parse-as-library \
  AgentUI/Models/Workspace.swift AgentUI/Models/WorkspaceStore.swift AgentUI/Models/SidebarFilter.swift \
  AgentUI/Services/GitService.swift AgentUI/Services/GitRepository.swift AgentUI/Services/WorkspaceWriter.swift \
  AgentUI/Services/ReadCommand.swift AgentUI/Services/CommandRunner.swift \
  Tests/StoreTests.swift -o "$store_binary"
"$store_binary"
