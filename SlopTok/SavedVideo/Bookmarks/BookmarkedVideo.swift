import Foundation

// Model to represent a bookmarked video with timestamp
struct BookmarkedVideo: Identifiable, Equatable, SavedVideo {
    let id: String
    let timestamp: Date
    
    init(id: String, timestamp: Date = Date()) {
        self.id = id
        self.timestamp = timestamp
    }
    
    static func == (lhs: BookmarkedVideo, rhs: BookmarkedVideo) -> Bool {
        lhs.id == rhs.id
    }
}
