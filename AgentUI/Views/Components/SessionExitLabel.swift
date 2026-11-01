import SwiftUI

struct SessionExitLabel: View {
    let code: Int32?

    private var title: String {
        switch code {
        case nil: "Session terminée"
        case 127: "Commande introuvable (127) : vérifie qu’elle est installée et dans le PATH de ton shell"
        case let code?: "Session terminée (\(code))"
        }
    }

    var body: some View {
        Label(title, systemImage: "stop.circle")
    }
}
