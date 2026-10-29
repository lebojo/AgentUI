import SwiftUI

struct RemoteSummary: View {
    let model: InspectorStore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(model.remote?.hosting.title ?? "Dépôt distant").font(Typography.sectionTitle)
            if let remote = model.remote {
                if let url = URL(string: remote.repository.url) { Link(remote.repository.nameWithOwner, destination: url).lineLimit(2) }
                if let pr = remote.changeRequest {
                    if let url = URL(string: pr.url) { Link("\(remote.hosting.changeRequestPrefix)\(pr.number) · \(pr.title)", destination: url).font(Typography.body) }
                    Text("\(pr.isDraft ? "Brouillon" : pr.state) · \(pr.headRefName) → \(pr.baseRefName)")
                        .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                } else if let error = remote.changeRequestError {
                    InspectorNotice(title: "\(remote.hosting.changeRequestTitle) indisponible", message: error)
                } else {
                    Text("Aucune \(remote.hosting.changeRequestTitle.lowercased()) pour cette branche.")
                        .font(Typography.body).foregroundStyle(Palette.textSecondary)
                }
            } else if let error = model.remoteError {
                InspectorNotice(title: "Dépôt distant indisponible", message: error)
            } else { Text("Chargement via gh ou glab…").font(Typography.body).foregroundStyle(Palette.textSecondary) }
        }
    }
}

struct RemoteChecks: View {
    let model: InspectorStore
    let headSHA: String?

    var body: some View {
        RemoteSummary(model: model)
        if let remote = model.remote {
            if let pr = remote.changeRequest, let checks = pr.statusCheckRollup, !checks.isEmpty {
                Divider()
                Text("Checks de la \(remote.hosting.changeRequestTitle.lowercased())").font(Typography.sectionTitle)
                if pr.headRefOid != headSHA {
                    Label("Ces checks concernent le commit distant de la \(remote.hosting.changeRequestTitle.lowercased()), différent du HEAD local.",
                          systemImage: "info.circle")
                        .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
                ForEach(checks) { check in CheckRow(title: check.title, result: check.result, url: check.url) }
            }
            Divider()
            Text("\(remote.hosting.runsTitle) · HEAD local").font(Typography.sectionTitle)
            if let headSHA { Text(String(headSHA.prefix(8))).font(Typography.captionMono).foregroundStyle(Palette.textSecondary) }
            if let error = remote.checksError {
                InspectorNotice(title: "\(remote.hosting.runsTitle) indisponibles", message: error)
            } else if remote.runs.isEmpty {
                Text(headSHA == nil ? "Aucun commit dans ce dépôt." : remote.hosting.noRunsMessage)
                    .font(Typography.body).foregroundStyle(Palette.textSecondary)
            }
            ForEach(remote.runs) { run in CheckRow(title: run.workflowName.isEmpty ? run.displayTitle : run.workflowName, result: run.result, url: run.url) }
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
