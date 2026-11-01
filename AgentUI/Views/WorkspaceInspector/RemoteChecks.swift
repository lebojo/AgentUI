import SwiftUI

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
