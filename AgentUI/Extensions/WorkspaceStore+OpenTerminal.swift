import Foundation

extension WorkspaceStore {
    func openTerminal(projectID: UUID, worktreeID: UUID, launch: AgentLaunch) {
        do {
            _ = try addTerminal(projectID: projectID, worktreeID: worktreeID, command: launch.command(on: .newTerminal))
        }
        catch { errorMessage = error.localizedDescription }
    }

    func runAgent(prompt: String, name: String, projectID: UUID, worktreeID: UUID, launch: AgentLaunch) {
        do {
            _ = try addTerminal(projectID: projectID, worktreeID: worktreeID, name: name, command: launch.command(prompt: prompt))
        }
        catch { errorMessage = error.localizedDescription }
    }
}
