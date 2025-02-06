import Foundation

protocol SavedVideo: Identifiable, Equatable {
    var id: String { get }
    var timestamp: Date { get }
}

// Default implementation of Equatable to match existing behavior
extension SavedVideo {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
