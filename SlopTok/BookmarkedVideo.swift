import SwiftUI

struct BookmarkedVideo: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    let folderId: String?
    
    static func == (lhs: BookmarkedVideo, rhs: BookmarkedVideo) -> Bool {
        lhs.id == rhs.id
    }
}
