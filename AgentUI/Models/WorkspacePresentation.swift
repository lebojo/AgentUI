import Observation

@MainActor @Observable final class WorkspacePresentation {
    var sheet: WorkspaceSheet?
    var removal: Removal?
}
