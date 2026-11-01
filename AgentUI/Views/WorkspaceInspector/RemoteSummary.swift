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
