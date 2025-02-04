import SwiftUI
import AVKit
import FirebaseStorage

struct BookmarksGridView: View {
    @ObservedObject var bookmarksService: BookmarksService
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selectedVideoIndex: Int? = nil
    @State private var videoPlayerSelection: BookmarkVideoSelection? = nil
    
    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(bookmarksService.bookmarkedVideos.enumerated()), id: \.element.id) { index, video in
                    VideoThumbnail(videoId: video.id, thumbnail: thumbnails[video.id])
                        .onAppear {
                            generateThumbnail(for: video.id)
                        }
                        .onTapGesture {
                            let sortedVideos = bookmarksService.bookmarkedVideos.sorted(by: { $0.timestamp > $1.timestamp })
                            videoPlayerSelection = BookmarkVideoSelection(
                                videos: sortedVideos,
                                selectedVideoId: video.id
                            )
                        }
                }
            }
        }
        .task {
            await bookmarksService.loadBookmarkedVideos()
        }
        .fullScreenCover(item: $videoPlayerSelection) { selection in
            if let index = selection.videos.firstIndex(where: { $0.id == selection.selectedVideoId }) {
                BookmarkedVideoPlayerView(
                    bookmarkedVideos: selection.videos,
                    initialIndex: index,
                    bookmarksService: bookmarksService
                )
            } else {
                BookmarkedVideoPlayerView(
                    bookmarkedVideos: selection.videos,
                    initialIndex: 0,
                    bookmarksService: bookmarksService
                )
            }
        }
    }
    
private func generateThumbnail(for videoId: String) {
    if thumbnails[videoId] != nil { return }
    ThumbnailGenerator.generateThumbnail(for: videoId) { image in
        if let image = image {
            DispatchQueue.main.async {
                thumbnails[videoId] = image
            }
        }
    }
}
} 