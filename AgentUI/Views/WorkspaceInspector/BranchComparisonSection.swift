import SwiftUI

struct BranchComparisonSection: View {
    @State private var branches: GitBranchList?
    @State private var comparison: BranchComparison?
    @State private var comparisonTree = GitChangeFolder.empty
    @State private var branchesError: String?
    @State private var comparisonError: String?

    @Binding var base: ComparisonBranch?

    let root: String
    let headSHA: String
    let refresh: Int
    let context: TerminalContext
    let source: any InspectorSource

    private var currentComparison: BranchComparison? {
        comparison.flatMap { $0.base == base ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Branch Comparison").font(Typography.sectionTitle)
            if let branchesError {
                InspectorNotice(title: "Branches Unavailable", message: branchesError)
            }
            if let branches, branches.branches.isEmpty {
                Text("No other branch to compare with.").font(Typography.body).foregroundStyle(Palette.textSecondary)
            } else if let branches {
                Picker("Compare With", selection: $base) {
                    ForEach(branches.branches) { branch in
                        Text(branch.name).tag(Optional(branch))
                    }
                }
                .pickerStyle(.menu)
                .font(Typography.body)
                if branches.omitted > 0 {
                    Text("\(branches.omitted) older branches not listed").font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
            }
            if let comparisonError {
                InspectorNotice(title: "Comparison Unavailable", message: comparisonError)
            } else if let comparison = currentComparison {
                Text("\(comparison.commits) commits ahead of \(comparison.base.name)")
                    .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                #if os(macOS)
                if comparison.commits > 0 { ChangeRequestMenu(root: root, base: comparison.base, context: context, source: source) }
                #endif
                GitChangeList(root: root, scope: .branch(comparison.base), tree: comparisonTree, omitted: comparison.omittedChanges, source: source)
            } else if base != nil || (branches == nil && branchesError == nil) {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: refresh) { await loadBranches() }
        .task(id: "\(base?.reference ?? "")-\(headSHA)-\(refresh)") { await loadComparison() }
    }

    private func loadBranches() async {
        do {
            let found = try await source.branches(at: root)
            guard !Task.isCancelled else { return }
            branches = found
            branchesError = nil
            base = found.preferred(over: base)
        } catch {
            guard !Task.isCancelled else { return }
            branchesError = error.localizedDescription
        }
    }

    private func loadComparison() async {
        guard let base else { return }
        comparisonError = nil
        do {
            let found = try await source.comparison(with: base, at: root)
            let tree = await GitChangeFolder.build(found.changes)
            guard !Task.isCancelled else { return }
            comparison = found
            comparisonTree = tree
        } catch {
            guard !Task.isCancelled else { return }
            comparisonError = error.localizedDescription
        }
    }
}
