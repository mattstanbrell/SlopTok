import Foundation

// Protocol for video models
protocol VideoModel: Identifiable {
    var id: String { get }
    var timestamp: Date { get }
}

// Extend existing models to conform to VideoModel
extension LikedVideo: VideoModel {}
extension BookmarkedVideo: VideoModel {}