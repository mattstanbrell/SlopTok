import SwiftUI
import AVKit
import FirebaseAuth

struct ContentView: View {
    let videos = ["man", "skyline", "water"]  // In a real app, there would be more entries.
    @State private var isDotExpanded = false
    @State private var scrollPosition: Int?
    @StateObject private var likesService = LikesService()
    @StateObject private var bookmarksService = BookmarksService()
    @State private var currentVideoLiked = false
    
    var userName: String {
        Auth.auth().currentUser?.displayName ?? "User"
    }
    
    var currentVideoId: String {
        let position = scrollPosition ?? 0
        return position < videos.count ? videos[position] : videos[0]
    }
    
    private func updateCurrentVideoLikedStatus() {
        let position = scrollPosition ?? 0
        if position >= 0 && position < videos.count {
            let video = videos[position]
            withAnimation(.easeInOut(duration: 0.2)) {
                currentVideoLiked = likesService.isLiked(videoId: video)
            }
        }
    }
    
    // Preload next 5 videos starting from the current index.
    private func preloadNextVideos(from index: Int) {
        let total = videos.count
        let maxIndex = min(index + 5, total - 1)
        if maxIndex <= index { return }
        for i in (index + 1)...maxIndex {
            let resource = videos[i]
            VideoURLCache.shared.getVideoURL(for: resource) { url in
                if let url = url {
                    VideoFileCache.shared.getLocalVideoURL(for: resource, remoteURL: url) { _ in
                        // Preloaded video file.
                    }
                }
            }
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.offset) { index, video in
                        ZStack {
                            LoopingVideoView(
                                videoResource: video,
                                likesService: likesService,
                                isVideoLiked: Binding(
                                    get: { likesService.isLiked(videoId: video) },
                                    set: { _ in
                                        if index == (scrollPosition ?? 0) {
                                            updateCurrentVideoLikedStatus()
                                        }
                                    }
                                )
                            )
                            
                            if isDotExpanded {
                                Color.clear
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            isDotExpanded = false
                                        }
                                    }
                            }
                        }
                        .frame(width: UIScreen.main.bounds.width,
                               height: UIScreen.main.bounds.height)
                        .clipped()
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .ignoresSafeArea()
            .scrollPosition(id: $scrollPosition)
            .onChange(of: scrollPosition) { newPosition in
                updateCurrentVideoLikedStatus()
                preloadNextVideos(from: newPosition ?? 0)
                
                if isDotExpanded {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isDotExpanded = false
                    }
                }
            }
            .onReceive(likesService.$likedVideos) { _ in
                if scrollPosition == nil {
                    scrollPosition = 0
                }
                updateCurrentVideoLikedStatus()
            }
            .task {
                await likesService.loadLikedVideos()
                await bookmarksService.loadBookmarkedVideos()
                updateCurrentVideoLikedStatus()
            }
            .zIndex(0)
            
            ControlDotView(
                isExpanded: $isDotExpanded,
                userName: userName,
                dotColor: currentVideoLiked ? .red : .white,
                likesService: likesService,
                bookmarksService: bookmarksService,
                currentVideoId: currentVideoId,
                onBookmarkAction: nil,
                onProfileAction: nil
            )
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .center)
            .zIndex(2)
        }
    }
}