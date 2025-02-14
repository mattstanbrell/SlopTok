import Foundation

// Model to represent a bookmark folder
struct BookmarkFolder: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let timestamp: Date
    let videoCount: Int
    
    init(id: String = UUID().uuidString, name: String, timestamp: Date = Date(), videoCount: Int = 0) {
        self.id = id
        self.name = name
        self.timestamp = timestamp
        self.videoCount = videoCount
    }
    
    static func == (lhs: BookmarkFolder, rhs: BookmarkFolder) -> Bool {
        lhs.id == rhs.id
    }
}

// Model to represent a bookmarked video with timestamp and folders
struct BookmarkedVideo: Codable, Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let folderIds: [String]
    
    init(id: String, timestamp: Date = Date(), folderIds: [String] = []) {
        self.id = id
        self.timestamp = timestamp
        self.folderIds = folderIds
    }
    
    static func == (lhs: BookmarkedVideo, rhs: BookmarkedVideo) -> Bool {
        lhs.id == rhs.id
    }
}
