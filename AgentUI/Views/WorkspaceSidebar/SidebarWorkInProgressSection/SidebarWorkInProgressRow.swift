import SwiftUI

struct SidebarWorkInProgressRow: View {
    let row: WorkInProgressRow

    var body: some View {
        switch row {
        case .status(let status, let count):
            SidebarStatusHeader(status: status, count: count)
        case .terminal(let item):
            SidebarWorkInProgressItemRow(item: item)
        }
    }
}
