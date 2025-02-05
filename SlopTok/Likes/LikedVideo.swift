import SwiftUI

// Model to represent a liked video with timestamp
struct LikedVideo: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    
    static func == (lhs: LikedVideo, rhs: LikedVideo) -> Bool {
        lhs.id == rhs.id
    }
}
