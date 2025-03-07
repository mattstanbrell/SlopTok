import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import AVFoundation

struct FolderContentsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bookmarksService: BookmarksService
    let folder: BookmarkFolder
    @State private var selectedVideoId: String?
    @State private var showingGeneratedVideos = false
    @State private var isGenerating = false
    @State private var generatedVideoIds: [String] = []
    @State private var profileLoadError: String?
    
    private var folderVideos: [BookmarkedVideo] {
        bookmarksService.bookmarkedVideos.filter { $0.folderIds.contains(folder.id) }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    // Generate More button
                    Button {
                        generateMoreVideos()
                    } label: {
                        HStack {
                            Image(systemName: "wand.and.stars")
                            Text("Generate More")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)
                    .disabled(isGenerating || folderVideos.isEmpty)
                    
                    if isGenerating {
                        ProgressView()
                            .padding()
                    }
                    
                    if let error = profileLoadError {
                        Text(error)
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 1),
                        GridItem(.flexible(), spacing: 1),
                        GridItem(.flexible(), spacing: 1)
                    ], spacing: 1) {
                        ForEach(folderVideos) { video in
                            VideoThumbnailView(videoId: video.id)
                                .aspectRatio(9/16, contentMode: .fill)
                                .onTapGesture {
                                    selectedVideoId = video.id
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        removeFromFolder(videoId: video.id)
                                    } label: {
                                        Label("Remove from Folder", systemImage: "folder.badge.minus")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle(folder.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            deleteFolder()
                        } label: {
                            Label("Delete Folder", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedVideoId) { videoId in
            BookmarkedVideoPlayerView(
                bookmarkedVideos: folderVideos,
                initialIndex: folderVideos.firstIndex(where: { $0.id == videoId }) ?? 0,
                bookmarksService: bookmarksService
            )
        }
        .fullScreenCover(isPresented: $showingGeneratedVideos) {
            VideoSwiperView(
                bookmarksService: bookmarksService,
                folder: folder,
                generatedVideoIds: generatedVideoIds
            )
            .presentationBackground(.clear)
            .interactiveDismissDisabled()
        }
    }
    
    private func removeFromFolder(videoId: String) {
        Task {
            do {
                try await bookmarksService.removeVideoFromFolder(videoId: videoId, folderId: folder.id)
            } catch {
                print("Error removing video from folder: \(error)")
            }
        }
    }
    
    private func deleteFolder() {
        Task {
            do {
                try await bookmarksService.deleteFolder(folderId: folder.id)
                dismiss()
            } catch {
                print("Error deleting folder: \(error)")
            }
        }
    }
    
    private func generateMoreVideos() {
        guard !folderVideos.isEmpty else { return }
        isGenerating = true
        profileLoadError = nil
        print("🎬 Starting video generation for folder: \(folder.name)")
        
        Task {
            do {
                // Wait for profile to be loaded
                for attempt in 0..<3 {  // Try up to 3 times
                    if let profile = await ProfileService.shared.currentProfile {
                        // Get prompts from video interactions
                        let db = Firestore.firestore()
                        guard let userId = Auth.auth().currentUser?.uid else { return }
                        
                        print("👤 Got user profile, fetching video interactions")
                        
                        // Get all video interactions in a single query
                        let querySnapshot = try await db.collection("users")
                            .document(userId)
                            .collection("videoInteractions")
                            .whereField(FieldPath.documentID(), in: folderVideos.map { $0.id })
                            .getDocuments()
                        
                        var videosWithPrompts: [LikedVideo] = []
                        let documents = Dictionary(uniqueKeysWithValues: querySnapshot.documents.map { ($0.documentID, $0) })
                        
                        // Maintain order from folderVideos
                        for video in folderVideos {
                            if let doc = documents[video.id],
                               let prompt = doc.data()["prompt"] as? String {
                                videosWithPrompts.append(LikedVideo(id: video.id, timestamp: video.timestamp, prompt: prompt))
                            }
                        }
                        
                        print("📝 Found \(videosWithPrompts.count) videos with prompts out of \(folderVideos.count) total")
                        
                        // Generate new videos using folder-specific generation
                        print("🎨 Starting folder-specific video generation")
                        let videoIds = try await VideoGenerator.shared.generateFolderVideos(
                            likedVideos: videosWithPrompts,
                            profile: profile
                        )
                        print("✅ Generated \(videoIds.count) new videos: \(videoIds)")
                        
                        await MainActor.run {
                            print("🔄 Updating UI with generated videos")
                            self.generatedVideoIds = videoIds
                            self.isGenerating = false
                            self.showingGeneratedVideos = true
                            print("🎯 Set showingGeneratedVideos to true")
                        }
                        return
                    } else {
                        print("⏳ Profile not loaded, attempt \(attempt + 1)/3")
                        // Wait a bit before retrying
                        try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * Double(attempt + 1)))
                    }
                }
                
                // If we get here, we failed to get the profile after retries
                print("❌ Failed to load profile after 3 attempts")
                await MainActor.run {
                    self.profileLoadError = "Could not load user profile. Please try again."
                    self.isGenerating = false
                }
            } catch {
                print("❌ Error generating videos: \(error)")
                await MainActor.run {
                    self.profileLoadError = "Error generating videos: \(error.localizedDescription)"
                    self.isGenerating = false
                }
            }
        }
    }
}

struct VideoSwiperView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bookmarksService: BookmarksService
    @StateObject private var likesService = LikesService()
    let folder: BookmarkFolder
    let generatedVideoIds: [String]
    
    @State private var currentIndex = 0
    @State private var offset: CGFloat = 0
    @State private var isSwiping = false
    @State private var isAnimatingTransition = false
    @State private var lastPreloadedIndex = -1  // Track last preload index
    @State private var isDismissing = false  // Add this state variable
    
    private var currentVideoId: String? {
        guard currentIndex < generatedVideoIds.count else { 
            print("⚠️ Current index \(currentIndex) exceeds video count \(generatedVideoIds.count)")
            return nil 
        }
        let id = generatedVideoIds[currentIndex]
        print("📺 Current video ID: \(id) at index \(currentIndex)")
        return id
    }
    
    private var nextVideoId: String? {
        guard currentIndex + 1 < generatedVideoIds.count else { 
            print("⚠️ Next index \(currentIndex + 1) exceeds video count \(generatedVideoIds.count)")
            return nil 
        }
        let id = generatedVideoIds[currentIndex + 1]
        print("⏭️ Next video ID: \(id) at index \(currentIndex + 1)")
        return id
    }
    
    private func preloadNextVideos(from index: Int) {
        // Don't preload if we've already preloaded from this index
        if index == lastPreloadedIndex { return }
        lastPreloadedIndex = index
        
        let total = generatedVideoIds.count
        let maxIndex = min(index + 2, total - 1)  // Preload up to 2 videos ahead
        if maxIndex <= index { return }
        
        print("🔄 Preloading videos from index \(index) to \(maxIndex)")
        
        // Update player cache position but don't clear old players
        if let currentId = currentVideoId {
            PlayerCache.shared.updatePosition(current: currentId)
        }
        
        // Preload next videos
        for i in (index + 1)...maxIndex {
            let videoId = generatedVideoIds[i]
            
            // Skip if already preloaded
            if PlayerCache.shared.hasPlayer(for: videoId) {
                continue
            }
            
            // Ensure thumbnail is loaded first
            Task {
                _ = await VideoService.shared.getUIImageThumbnail(for: videoId)
            }
            
            VideoURLCache.shared.getVideoURL(for: videoId) { url in
                if let url = url {
                    VideoFileCache.shared.getLocalVideoURL(for: videoId, remoteURL: url) { localURL in
                        if let localURL = localURL {
                            print("✅ Preloaded video: \(videoId)")
                            let player = AVPlayer(url: localURL)
                            
                            // Configure for optimal playback
                            player.automaticallyWaitsToMinimizeStalling = false
                            
                            // Start loading the video immediately
                            player.replaceCurrentItem(with: AVPlayerItem(url: localURL))
                            player.seek(to: .zero)
                            
                            // Store the player first
                            PlayerCache.shared.setPlayer(player, for: videoId)
                            
                            // Add to rate observer to detect when ready
                            _ = player.observe(\.timeControlStatus) { player, _ in
                                if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                                    // Video is buffered and ready
                                    print("🎥 Video ready to play: \(videoId)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        ZStack {
            // Background color with fade animation
            Color.black.opacity(isDismissing ? 0 : 0.6)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.2), value: isDismissing)
            
            // Stack of cards
            ZStack {
                // Next card (if any)
                if let nextId = nextVideoId {
                    VideoPlayerView(
                        videoResource: nextId,
                        likesService: likesService,
                        isVideoLiked: Binding(
                            get: { likesService.isLiked(videoId: nextId) },
                            set: { _ in }
                        )
                    )
                    .id("next-\(nextId)")
                    .frame(width: UIScreen.main.bounds.width * 0.85)
                    .aspectRatio(9/16, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .scaleEffect(0.95)
                    .padding(.top, 60)
                    .opacity(isAnimatingTransition ? 1 : 0.7)  // Make opaque during transition
                    .animation(.easeOut(duration: 0.2), value: isAnimatingTransition)
                    .onAppear {
                        print("🎴 Rendering next card: \(nextId)")
                        // Ensure next video is ready to play
                        if let player = PlayerCache.shared.getPlayer(for: nextId) {
                            player.seek(to: .zero)
                            // Don't start playing, just ensure it's buffered
                            player.pause()
                        }
                    }
                }
                
                // Current card
                if let videoId = currentVideoId {
                    VideoPlayerView(
                        videoResource: videoId,
                        likesService: likesService,
                        isVideoLiked: Binding(
                            get: { likesService.isLiked(videoId: videoId) },
                            set: { _ in }
                        )
                    )
                    .id("current-\(videoId)")
                    .frame(width: UIScreen.main.bounds.width * 0.85)
                    .aspectRatio(9/16, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .offset(x: offset)
                    .rotationEffect(.degrees(Double(offset) / 20))
                    .padding(.top, 60)
                    .opacity(isDismissing || isAnimatingTransition ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: isDismissing)
                    .onAppear {
                        print("🎴 Rendering current card: \(videoId)")
                        // Start playing current video
                        if let player = PlayerCache.shared.getPlayer(for: videoId) {
                            player.seek(to: .zero)
                            player.play()
                        }
                    }
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                print("👆 Drag changed: \(gesture.translation.width)")
                                isSwiping = true
                                withAnimation(.interactiveSpring()) {
                                    offset = gesture.translation.width
                                }
                            }
                            .onEnded { gesture in
                                print("👆 Drag ended: \(gesture.translation.width)")
                                let width = UIScreen.main.bounds.width
                                if abs(offset) > width * 0.4 {
                                    // Swipe threshold met
                                    let direction = offset > 0
                                    print("✨ Swipe threshold met: \(direction ? "right" : "left")")
                                    
                                    // Add to folder if swiped right
                                    if direction {
                                        print("📁 Adding to folder: \(videoId)")
                                        addToFolder(videoId: videoId)
                                    }
                                    
                                    print("🎬 Starting swipe animation")
                                    isAnimatingTransition = true
                                    
                                    // First animate the card off screen
                                    withAnimation(.spring()) {
                                        offset = direction ? width : -width
                                    }
                                    
                                    // Then update the index after animation completes
                                    print("⏰ Scheduling index update")
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        print("📱 Updating index from \(currentIndex) to \(currentIndex + 1)")
                                        currentIndex += 1
                                        offset = 0
                                        isAnimatingTransition = false
                                        print("🔄 Reset offset to 0")
                                        if currentIndex >= generatedVideoIds.count {
                                            print("🏁 No more videos, dismissing")
                                            isDismissing = true
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                dismiss()
                                            }
                                        }
                                    }
                                } else {
                                    print("↩️ Reset position - threshold not met")
                                    // Reset position
                                    withAnimation(.spring()) {
                                        offset = 0
                                    }
                                }
                                isSwiping = false
                            }
                    )
                    .onTapGesture(count: 2) {
                        print("👆 Double tap detected")
                        // Double tap to like
                        print("📁 Adding to folder: \(videoId)")
                        addToFolder(videoId: videoId)
                        
                        print("🎬 Starting swipe animation")
                        isAnimatingTransition = true
                        
                        // First animate the card off screen
                        withAnimation(.spring()) {
                            offset = UIScreen.main.bounds.width
                        }
                        
                        // Then update the index after animation completes
                        print("⏰ Scheduling index update")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            print("📱 Updating index from \(currentIndex) to \(currentIndex + 1)")
                            currentIndex += 1
                            offset = 0
                            isAnimatingTransition = false
                            print("🔄 Reset offset to 0")
                            if currentIndex >= generatedVideoIds.count {
                                print("🏁 No more videos, dismissing")
                                isDismissing = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    dismiss()
                                }
                            }
                        }
                    }
                } else {
                    Text("No videos to display")
                        .foregroundColor(.white)
                        .padding(.top, 60)
                }
            }
            .onChange(of: currentIndex) { newIndex in
                print("🔄 Current index changed to: \(newIndex)")
                print("📊 Total videos: \(generatedVideoIds.count)")
                
                // Don't clear the cache, just preload next videos
                preloadNextVideos(from: newIndex)
            }
            
            // Swipe indicators
            HStack {
                Image(systemName: "x.circle.fill")
                    .foregroundColor(.red)
                    .opacity(offset < 0 ? min(abs(Double(offset) / 100), 1.0) : 0)
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .opacity(offset > 0 ? min(Double(offset) / 100, 1.0) : 0)
            }
            .font(.system(size: 50))
            .padding(40)
            .padding(.top, 60)
        }
        .presentationBackground(.clear)
        .onAppear {
            print("🎬 VideoSwiperView appeared")
            print("📊 Total videos: \(generatedVideoIds.count)")
            print("🎯 Starting index: \(currentIndex)")
            print("🎥 Video IDs: \(generatedVideoIds)")
            
            // Start preloading from the first video
            preloadNextVideos(from: currentIndex)
        }
    }
    
    private func addToFolder(videoId: String) {
        Task {
            do {
                print("📁 Starting folder add for video: \(videoId)")
                try await bookmarksService.addVideoToFolders(
                    videoId: videoId,
                    folderIds: [folder.id]
                )
                print("✅ Successfully added to folder")
            } catch {
                print("❌ Error adding video to folder: \(error)")
            }
        }
    }
}

struct GeneratedVideosSwiperView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bookmarksService: BookmarksService
    let folder: BookmarkFolder
    let generatedVideos: [String] // Array of video IDs
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Swipe right to add to folder\nSwipe left to discard")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding()
                
                Spacer()
                Text("TODO: Implement swiper view")
                Spacer()
            }
            .navigationTitle("Generated Videos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
} 