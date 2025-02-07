import SwiftUI
import AVKit
import FirebaseAuth

struct MainFeedView: View {
    @State private var videos = ["water", "skyline", "IMG_0371"]  // In a real app, there would be more entries.
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
        
        // Preload current video's comments
        CommentsService.shared.preloadComments(for: videos[index])
        
        // Update player cache position tracking
        PlayerCache.shared.updatePosition(current: videos[index])
        
        var needsPreload = false
        for i in indicesToPreload {
            if !PlayerCache.shared.hasPlayer(for: videos[i]) {
                needsPreload = true
                break
            }
        }
        
        if !needsPreload { return }
        
        for i in indicesToPreload {
            let resource = videos[i]
            // Skip if already preloaded
            if PlayerCache.shared.hasPlayer(for: resource) { continue }
            
            // Check if we have the video file cached
            let localURL = VideoFileCache.shared.localFileURL(for: resource)
            if FileManager.default.fileExists(atPath: localURL.path) {
                createAndCachePlayer(for: resource, url: localURL)
                continue
            }
            
            // If not in file cache, get the URL and download
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
                
                ScrollView(.vertical, showsIndicators: false) {
                    // 👇 MINIMAL FIX: Use the video itself as the ForEach ID
                    //    This way SwiftUI re‐diffs the top row if the video changes.
                    VStack(spacing: 0) {
                        ForEach(Array(videos.enumerated()), id: \.element) { (index, video) in
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
                            // Keep .id(index) so ScrollViewReader & .scrollPosition work by offset
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
                    
                    await likesService.loadLikedVideos()
                    await bookmarksService.loadBookmarkedVideos()
                    updateCurrentVideoLikedStatus()
                    
                    print("📱 MainFeedView - Current videos: \(videos)")
                    
                    // If we have an initial video from deep link, insert it at the top
                    if let sharedVideoId = initialVideoId {
                        print("📱 MainFeedView - Attempting to insert shared video: \(sharedVideoId)")
                        
                        if !videos.contains(sharedVideoId) {
                            print("📱 MainFeedView - Video not in feed, inserting at top")
                            videos.insert(sharedVideoId, at: 0)
                            print("📱 MainFeedView - Updated videos: \(videos)")
                        } else {
                            // If video exists, remove it and reinsert at top
                            print("📱 MainFeedView - Video exists in feed, moving to top")
                            videos.removeAll { $0 == sharedVideoId }
                            videos.insert(sharedVideoId, at: 0)
                            print("📱 MainFeedView - Updated videos after move: \(videos)")
                        }
                        
                        // Reset scroll position to show shared video
                        print("📱 MainFeedView - Resetting scroll position to 0")
                        scrollPosition = 0
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
                    }
                    
                    print("📱 MainFeedView - Final videos array: \(videos)")
                    print("📱 MainFeedView - Final scroll position: \(String(describing: scrollPosition))")
                    preloadNextVideos(from: scrollPosition ?? 0)
                }
                .onChange(of: initialVideoId) { newVideoId in
                    if let videoId = newVideoId,
                       let index = videos.firstIndex(of: videoId) {
                        withAnimation {
                            scrollPosition = index
                        }
                        preloadNextVideos(from: index)
                    }
                }
                .zIndex(0)
                
                // Show share info if this is a shared video and we're at the first position
                if scrollPosition == 0,
                   let sharedByInfo = sharedByInfo {
                    VStack {
                        ShareInfoView(userName: sharedByInfo.userName, timestamp: sharedByInfo.timestamp)
                        Spacer()
                    }
                }
                
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
}
