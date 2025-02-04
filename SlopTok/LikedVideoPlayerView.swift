import SwiftUI
import FirebaseAuth

struct LikedVideoPlayerView: View {
    // Environment
    @Environment(\.dismiss) private var dismiss
    
    // Dependencies passed in
    let likesService: LikesService
    
    // Configuration
    let initialIndex: Int
    
    // Local state
    @State private var videos: [VideoPlayerData]
    @State private var currentIndex: Int
    @State private var isDotExpanded = false
    
    init(likedVideos: [LikedVideo], initialIndex: Int, likesService: LikesService) {
        self.likesService = likesService
        self.initialIndex = initialIndex
        
        // Create initial video data with indices
        let videoData = likedVideos.enumerated().map { index, video in
            VideoPlayerData(id: video.id, timestamp: video.timestamp, index: index)
        }
        
        // Initialize state
        _videos = State(initialValue: videoData)
        _currentIndex = State(initialValue: initialIndex)
    }
    
    var currentVideo: VideoPlayerData? {
        videos.first { $0.index == currentIndex }
    }
    
    var body: some View {
        Group {
            if videos.isEmpty {
                Color.clear.onAppear { dismiss() }
            } else {
                videoPlayerView
            }
        }
    }
    
    private var videoPlayerView: some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(videos) { video in
                        VideoPlayerCell(
                            video: video,
                            isCurrentVideo: video.index == currentIndex,
                            onUnlike: { handleUnlike(video) },
                            likesService: likesService
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .ignoresSafeArea()
            
            ControlDotView(
                isExpanded: $isDotExpanded,
                userName: Auth.auth().currentUser?.displayName ?? "User",
                dotColor: .red,
                likesService: likesService
            )
            .padding(.top, 0)
            .frame(maxWidth: .infinity, alignment: .center)
            .zIndex(2)
        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    if gesture.translation.width > 100 {
                        dismiss()
                    }
                }
        )
    }
    
    private func handleUnlike(_ video: VideoPlayerData) {
        // First find where we should scroll to
        let nextIndex: Int?
        if video.index == videos.count - 1 {
            // If unliking last video, scroll up
            nextIndex = video.previous
        } else {
            // Otherwise stay at same position to show next video
            nextIndex = video.index
        }
        
        // Update local state first
        withAnimation {
            // Remove the video
            videos.removeAll { $0.id == video.id }
            
            // Reindex remaining videos
            for i in 0..<videos.count {
                videos[i] = VideoPlayerData(
                    id: videos[i].id,
                    timestamp: videos[i].timestamp,
                    index: i
                )
            }
            
            // Update scroll position
            if let next = nextIndex {
                currentIndex = next
            }
        }
        
        // Then update Firestore
        likesService.toggleLike(videoId: video.id)
    }
}
