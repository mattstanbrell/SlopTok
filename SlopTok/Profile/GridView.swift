import SwiftUI

// Allow String to be used as Identifiable for fullScreenCover
extension String: Identifiable {
    public var id: String { self }
}

struct GridView<T: VideoModel, FullScreenView: View>: View {
    let videos: [T]
    let columns: [GridItem]
    let gridSpacing: CGFloat
    let gridPadding: CGFloat
    let fullscreenContent: (_ sortedVideos: [T], _ selectedVideoId: String) -> FullScreenView

    // Convenience initializer with default grid parameters
    init(videos: [T],
         gridColumns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 1), count: 3),
         gridSpacing: CGFloat = 1,
         gridPadding: CGFloat = 0,
         fullscreenContent: @escaping (_ sortedVideos: [T], _ selectedVideoId: String) -> FullScreenView) {
        self.videos = videos
        self.columns = gridColumns
        self.gridSpacing = gridSpacing
        self.gridPadding = gridPadding
        self.fullscreenContent = fullscreenContent
    }

    @State private var thumbnails: [String: Image] = [:]
    @State private var selectedVideoId: String? = nil

    var body: some View {
        let sortedVideos = videos.sorted { $0.timestamp > $1.timestamp }
        
        ScrollView {
            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(sortedVideos, id: \.id) { video in
                    VideoThumbnail(videoId: video.id, thumbnail: thumbnails[video.id])
                        .onAppear {
                            getThumbnail(for: video.id)
                        }
                        .onTapGesture {
                            selectedVideoId = video.id
                        }
                }
            }
            .padding(gridPadding)
        }
        .fullScreenCover(item: $selectedVideoId) { videoId in
            fullscreenContent(sortedVideos, videoId)
        }
    }

    private func getThumbnail(for videoId: String) {
        if thumbnails[videoId] != nil { return }
        
        Task {
            if let image = await ThumbnailGenerator.getThumbnail(for: videoId) {
                await MainActor.run {
                    thumbnails[videoId] = image
                }
            }
        }
    }
}