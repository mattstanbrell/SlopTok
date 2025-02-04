import SwiftUI

// Model to hold a static snapshot of bookmarked videos for the player,
// and the ID of the selected video.
struct BookmarkVideoSelection: Identifiable {
    let id = UUID()
    let videos: [BookmarkedVideo]
    let selectedVideoId: String
} 