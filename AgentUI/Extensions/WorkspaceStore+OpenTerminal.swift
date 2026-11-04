import Foundation

extension WorkspaceStore {
    func openTerminal(_ project: Project, _ worktree: Worktree, launch: AgentLaunch) {
        do {
            _ = try addTerminal(projectID: project.id, worktreeID: worktree.id, command: launch.command(on: .newTerminal))
        }
        catch { errorMessage = error.localizedDescription }
    }

    func runAgent(prompt: String, name: String, in project: Project, _ worktree: Worktree, launch: AgentLaunch) {
        do {
            _ = try addTerminal(projectID: project.id, worktreeID: worktree.id, name: name, command: launch.command(prompt: prompt))
        }
        catch { errorMessage = error.localizedDescription }
    }
}
