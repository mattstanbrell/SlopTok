import SwiftUI
import AVKit
import FirebaseAuth

struct MainFeedView: View {
    @StateObject private var videoService = VideoService.shared
    @State private var isDotExpanded = false
    @State private var scrollPosition: Int?
    @StateObject private var likesService = LikesService()
    @StateObject private var bookmarksService = BookmarksService()
    @State private var currentVideoLiked = false
    @State private var lastPreloadedIndex = -1  // Track last preload index
    @State private var sharedByInfo: (userName: String, timestamp: Date)?
    @State private var hasInsertedSharedVideo = false  // Track if we've inserted the shared video
    
    let initialVideoId: String?
    let shareId: String?
    
    init(initialVideoId: String? = nil, shareId: String? = nil) {
        self.initialVideoId = initialVideoId
        self.shareId = shareId
    }
    
    var userName: String {
        Auth.auth().currentUser?.displayName ?? "User"
    }
    
    var currentVideoId: String {
        guard !videoService.videos.isEmpty else { return "" }
        let position = scrollPosition ?? 0
        return position < videoService.videos.count ? videoService.videos[position] : videoService.videos[0]
    }
    
    private func updateCurrentVideoLikedStatus() {
        let position = scrollPosition ?? 0
        if position >= 0 && position < videoService.videos.count {
            let video = videoService.videos[position]
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
        
        let total = videoService.videos.count
        
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
        
        // Preload current video's comments
        CommentsService.shared.preloadComments(for: videoService.videos[index])
        
        // Update player cache position tracking
        PlayerCache.shared.updatePosition(current: videoService.videos[index])
        
        // Preload videos that aren't already in the player cache
        for i in indicesToPreload {
            let resource = videoService.videos[i]
            // Skip if already preloaded
            if PlayerCache.shared.hasPlayer(for: resource) { continue }
            
            // Get the URL and download/create player
            VideoURLCache.shared.getVideoURL(for: resource) { url in
                if let url = url {
                    VideoFileCache.shared.getLocalVideoURL(for: resource, remoteURL: url) { localURL in
                        if let localURL = localURL {
                            self.createAndCachePlayer(for: resource, url: localURL)
                        }
                    }
                }
            }
        }
    }
    
    private func createAndCachePlayer(for videoId: String, url: URL) {
        let player = AVPlayer(url: url)
        player.automaticallyWaitsToMinimizeStalling = false
        PlayerCache.shared.setPlayer(player, for: videoId)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                if videoService.videos.isEmpty {
                    // Loading state
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading videos...")
                            .foregroundColor(.secondary)
                            .padding(.top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(videoService.videos.enumerated()), id: \.element) { (index, video) in
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
                            print("📱 MainFeedView - Scroll position changed to: \(position)")
                        }
                        
                        if isDotExpanded {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isDotExpanded = false
                            }
                        }
                    }
                }
                
                // Show share info if this is a shared video and we're at the first position
                if scrollPosition == 0,
                   let sharedByInfo = sharedByInfo {
                    VStack {
                        ShareInfoView(userName: sharedByInfo.userName, timestamp: sharedByInfo.timestamp)
                        Spacer()
                    }
                }
                
                if !videoService.videos.isEmpty {
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
        .onReceive(likesService.$likedVideos) { _ in
            if scrollPosition == nil {
                scrollPosition = 0
            }
            updateCurrentVideoLikedStatus()
        }
        .task {
            print("📱 MainFeedView - Task started")
            print("📱 MainFeedView - Initial video ID: \(String(describing: initialVideoId))")
            print("📱 MainFeedView - Share ID: \(String(describing: shareId))")
            
            // Load videos first
            await videoService.loadVideos()
            
            await likesService.loadLikedVideos()
            await bookmarksService.loadBookmarkedVideos()
            updateCurrentVideoLikedStatus()
            
            print("📱 MainFeedView - Current videos: \(videoService.videos)")
            
            // If we have an initial video from deep link, insert it at the top
            if let sharedVideoId = initialVideoId {
                print("📱 MainFeedView - Attempting to insert shared video: \(sharedVideoId)")
                
                if let index = videoService.videos.firstIndex(of: sharedVideoId) {
                    print("📱 MainFeedView - Video exists in feed, moving to top")
                    scrollPosition = index
                    print("📱 MainFeedView - Updated scroll position to: \(index)")
                }
                
                hasInsertedSharedVideo = true
                
                // If this is a shared video, fetch and show the share info
                if let shareId = shareId {
                    print("📱 MainFeedView - Fetching share info for ID: \(shareId)")
                    do {
                        sharedByInfo = try await ShareService.shared.getShareInfo(shareId: shareId)
                        print("📱 MainFeedView - Share info fetched: \(String(describing: sharedByInfo))")
                    } catch {
                        print("❌ MainFeedView - Error fetching share info: \(error)")
                    }
                }
            } else {
                print("📱 MainFeedView - No shared video to insert")
            }
            
            if scrollPosition == nil {
                print("📱 MainFeedView - Setting initial scroll position to 0")
                scrollPosition = 0
                // Only preload once we have a valid scroll position
                preloadNextVideos(from: 0)
            }
            
            print("📱 MainFeedView - Final videos array: \(videoService.videos)")
            print("📱 MainFeedView - Final scroll position: \(String(describing: scrollPosition))")
        }
        .onChange(of: initialVideoId) { newVideoId in
            if let videoId = newVideoId,
               let index = videoService.videos.firstIndex(of: videoId) {
                withAnimation {
                    scrollPosition = index
                }
                preloadNextVideos(from: index)
            }
        }
        .zIndex(0)
    }
}
