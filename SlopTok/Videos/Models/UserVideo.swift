import Foundation

struct UserVideo: VideoModel {
    let id: String
    let timestamp: Date
    let index: Int
    
    init(id: String, timestamp: Date, index: Int = 0) {
        self.id = id
        self.timestamp = timestamp
        self.index = index
    }
} 