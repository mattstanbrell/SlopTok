import SwiftUI

// Model to hold a static snapshot of bookmarked videos for the player
struct BookmarkVideoSelection: Identifiable {
    let id = UUID()
    let videos: [BookmarkedVideo]
    let index: Int
} 