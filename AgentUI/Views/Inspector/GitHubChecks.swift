import SwiftUI

struct GitHubSummary: View {
    let model: InspectorStore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("GitHub").font(Typography.sectionTitle)
            if let github = model.github {
                if let url = URL(string: github.repository.url) { Link(github.repository.nameWithOwner, destination: url).lineLimit(2) }
                if let pr = github.pullRequest {
                    if let url = URL(string: pr.url) { Link("#\(pr.number) · \(pr.title)", destination: url).font(Typography.body) }
                    Text("\(pr.isDraft ? "Brouillon" : pr.state) · \(pr.headRefName) → \(pr.baseRefName)")
                        .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                } else if let error = github.pullRequestError {
                    InspectorNotice(title: "Pull request indisponible", message: error)
                } else { Text("Aucune pull request pour cette branche.").font(Typography.body).foregroundStyle(Palette.textSecondary) }
            } else if let error = model.githubError {
                InspectorNotice(title: "Connexion GitHub indisponible", message: error)
            } else { Text("Chargement via gh…").font(Typography.body).foregroundStyle(Palette.textSecondary) }
        }
    }
}

struct GitHubChecks: View {
    let model: InspectorStore
    let headSHA: String?

    var body: some View {
        GitHubSummary(model: model)
        if let github = model.github {
            if let pr = github.pullRequest, let checks = pr.statusCheckRollup, !checks.isEmpty {
                Divider()
                Text("Checks de la pull request").font(Typography.sectionTitle)
                if pr.headRefOid != headSHA {
                    Label("Ces checks concernent le commit distant de la PR, différent du HEAD local.", systemImage: "info.circle")
                        .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
                ForEach(checks) { check in CheckRow(title: check.title, result: check.result, url: check.url) }
            }
            Divider()
            Text("Actions · HEAD local").font(Typography.sectionTitle)
            if let headSHA { Text(String(headSHA.prefix(8))).font(Typography.captionMono).foregroundStyle(Palette.textSecondary) }
            if let error = github.checksError {
                InspectorNotice(title: "Actions indisponibles", message: error)
            } else if github.runs.isEmpty {
                Text(headSHA == nil ? "Aucun commit dans ce dépôt." : "Aucune exécution GitHub Actions pour ce commit.")
                    .font(Typography.body).foregroundStyle(Palette.textSecondary)
            }
            ForEach(github.runs) { run in CheckRow(title: run.workflowName.isEmpty ? run.displayTitle : run.workflowName, result: run.result, url: run.url) }
        }
    }
}

private struct CheckRow: View {
    let title: String
    let result: String
    let url: String?

    private var status: (symbol: String, color: Color, title: String) {
        switch result.uppercased() {
        case "SUCCESS": ("checkmark.circle.fill", Palette.success, "Réussi")
        case "FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED": ("xmark.circle.fill", Palette.danger, "Échec")
        case "CANCELLED": ("slash.circle", Palette.textSecondary, "Annulé")
        case "SKIPPED", "NEUTRAL": ("minus.circle", Palette.textSecondary, "Ignoré")
        default: ("clock", Palette.warning, "En attente / en cours")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: status.symbol).foregroundStyle(status.color)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                if let url, let destination = URL(string: url) { Link(title, destination: destination) }
                else { Text(title) }
                Text(status.title).font(Typography.caption).foregroundStyle(Palette.textSecondary)
            }.font(Typography.body)
        }.padding(.vertical, Spacing.xxs)
    }
}
