import SwiftUI

extension DropEdge {
    var alignment: Alignment {
        switch self {
        case .leading: .leading
        case .trailing: .trailing
        case .top: .top
        case .bottom: .bottom
        }
    }
}
