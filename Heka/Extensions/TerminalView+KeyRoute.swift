import AppKit
import SwiftTerm

extension TerminalView {
    private var keyRouteScreen: TerminalKeyRoute.Screen {
        let terminal = getTerminal()
        return TerminalKeyRoute.Screen(usesKittyKeyboard: !terminal.keyboardEnhancementFlags.isEmpty,
                                       showsAlternateBuffer: terminal.isCurrentBufferAlternate,
                                       usesApplicationCursor: terminal.applicationCursor)
    }

    func routeKey(_ event: NSEvent) -> NSEvent? {
        guard !hasMarkedText(), let route = TerminalKeyRoute(key: event.specialKey, modifiers: event.modifierFlags,
                                           optionAsMeta: UserDefaults.standard.bool(forKey: TerminalKeyRoute.metaKeySetting),
                                           screen: keyRouteScreen) else { return event }
        switch route {
        case .composesCharacter:
            optionAsMetaKey = false
        case .actsAsMeta:
            optionAsMetaKey = true
        case .sends(let bytes):
            guard event.type == .keyDown else { return event }
            send(bytes)
            return nil
        }
        return event
    }
}
