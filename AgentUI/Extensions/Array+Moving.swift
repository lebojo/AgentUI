import SwiftUI

extension Array where Element: Identifiable {
    func moving(_ visible: [Element.ID], from source: IndexSet, to destination: Int) -> [Element]? {
        guard !source.isEmpty, source.allSatisfy(visible.indices.contains), (0...visible.count).contains(destination) else { return nil }
        var reorderedVisible = visible
        reorderedVisible.move(fromOffsets: source, toOffset: destination)
        guard reorderedVisible != visible else { return nil }
        let moved = source.map { visible[$0] }
        let movedIDs = Set(moved)
        let elements = moved.compactMap { id in first { $0.id == id } }
        guard elements.count == moved.count else { return nil }
        var result = filter { !movedIDs.contains($0.id) }
        let anchor = visible[destination...].first { !movedIDs.contains($0) }
        let previous = visible[..<destination].last { !movedIDs.contains($0) }
        let index = anchor.flatMap { id in result.firstIndex { $0.id == id } }
            ?? previous.flatMap { id in result.firstIndex { $0.id == id }.map { $0 + 1 } }
            ?? prefix { !movedIDs.contains($0.id) }.count
        result.insert(contentsOf: elements, at: index)
        return result
    }

    func removingAndAppending(at index: Int, _ element: Element) -> [Element] {
        var result = self
        result.remove(at: index)
        result.append(element)
        return result
    }
}
