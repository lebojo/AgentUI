import Foundation

extension String {
    var abbreviatingHome: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
