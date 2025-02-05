import SwiftUI
import AVKit
import FirebaseAuth

struct ContentView: View {
    let videos = ["man", "skyline", "water", "IMG_0371"]  // In a real app, there would be more entries.
    @State private var isDotExpanded = false
    @State private var scrollPosition: Int?
    @StateObject private var likesService = LikesService()
    @StateObject private var bookmarksService = BookmarksService()
    @State private var currentVideoLiked = false
    @State private var lastPreloadedIndex = -1  // Track last preload index
    
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
    
    // Preload 1 video above and 3 below the current index
    private func preloadNextVideos(from index: Int) {
        // Don't preload if we've already preloaded from this index
        if index == lastPreloadedIndex { return }
        lastPreloadedIndex = index
        
        let total = videos.count
        
        // Get indices to preload (1 above, 3 below)
        var indicesToPreload = [Int]()
        
        // Add one above if possible
        if index > 0 {
            indicesToPreload.append(index - 1)
        }
        
        // Add three below if possible
        for i in 1...3 {
            let nextIndex = index + i
            if nextIndex < total {
                indicesToPreload.append(nextIndex)
            }
        }
        
        if indicesToPreload.isEmpty { return }
        
        // Update player cache position tracking
        PlayerCache.shared.updatePosition(current: videos[index])
        
        // Only log if we actually need to preload something
        var needsPreload = false
        for i in indicesToPreload {
            if !PlayerCache.shared.hasPlayer(for: videos[i]) {
                needsPreload = true
                break
            }
        }
        
        if !needsPreload { return }
        
        VideoLogger.shared.log(.preloadStarted, videoId: "batch", 
            message: "Preloading videos (1 above, 3 below) around index \(index)")
        
        for i in indicesToPreload {
            let resource = videos[i]
            
            // Skip if already preloaded
            if PlayerCache.shared.hasPlayer(for: resource) { continue }
            
            VideoLogger.shared.log(.preloadStarted, videoId: resource, message: "Starting preload")
            
            // First check if we have the video file cached
            let localURL = VideoFileCache.shared.localFileURL(for: resource)
            if FileManager.default.fileExists(atPath: localURL.path) {
                VideoLogger.shared.log(.cacheHit, videoId: resource, message: "Found cached video file")
                createAndCachePlayer(for: resource, url: localURL)
                continue
            }
            
            // If not in file cache, get the URL and download
            VideoURLCache.shared.getVideoURL(for: resource) { url in
                if let url = url {
                    VideoFileCache.shared.getLocalVideoURL(for: resource, remoteURL: url) { localURL in
                        if let localURL = localURL {
                            self.createAndCachePlayer(for: resource, url: localURL)
                        } else {
                            VideoLogger.shared.log(.preloadFailed, videoId: resource, message: "Failed to get local URL")
                        }
                    }
                } else {
                    VideoLogger.shared.log(.preloadFailed, videoId: resource, message: "Failed to get video URL")
                }
            }
        }
    }
    
    private func createAndCachePlayer(for videoId: String, url: URL) {
        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = false
        PlayerCache.shared.setPlayer(player, for: videoId)
        VideoLogger.shared.log(.playerCreatedAndPreloadCompleted, videoId: videoId, message: "Created, cached, and preloaded player")
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.offset) { index, video in
                        ZStack {
                            VideoPlayerView(
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
                if let position = newPosition {
                    updateCurrentVideoLikedStatus()
                    preloadNextVideos(from: position)
                }
                
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
                // Start preloading from the first video immediately
                preloadNextVideos(from: 0)
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