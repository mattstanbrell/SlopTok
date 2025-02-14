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
    @State private var isSelectionMode = false
    @State private var selectedVideos: Set<String> = []
    
    private var folderVideos: [BookmarkedVideo] {
        bookmarksService.bookmarkedVideos.filter { $0.folderIds.contains(folder.id) }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if isSelectionMode {
                        HStack {
                            Button("Cancel") {
                                isSelectionMode = false
                                selectedVideos.removeAll()
                            }
                            .foregroundColor(.blue)
                            
                            Spacer()
                            
                            Button("Remove (\(selectedVideos.count))") {
                                Task {
                                    for videoId in selectedVideos {
                                        try? await bookmarksService.removeVideoFromFolder(videoId: videoId, folderId: folder.id)
                                    }
                                    isSelectionMode = false
                                    selectedVideos.removeAll()
                                }
                            }
                            .foregroundColor(.red)
                            .disabled(selectedVideos.isEmpty)
                        }
                        .padding(.horizontal)
                    }
                    
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
                                .overlay(
                                    ZStack {
                                        if isSelectionMode {
                                            Color.black.opacity(selectedVideos.contains(video.id) ? 0.5 : 0.0)
                                            if selectedVideos.contains(video.id) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .font(.title)
                                            }
                                        }
                                    }
                                )
                                .onTapGesture {
                                    if isSelectionMode {
                                        if selectedVideos.contains(video.id) {
                                            selectedVideos.remove(video.id)
                                        } else {
                                            selectedVideos.insert(video.id)
                                        }
                                    } else {
                                        selectedVideoId = video.id
                                    }
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
                        Button {
                            isSelectionMode = true
                        } label: {
                            Label("Remove Videos", systemImage: "minus.circle")
                        }
                        
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
        generatedVideoIds = []  // Reset the array
        
        Task {
            do {
                // Wait for profile to be loaded
                for attempt in 0..<3 {  // Try up to 3 times
                    if let profile = await ProfileService.shared.currentProfile {
                        // Get prompts from video interactions
                        let db = Firestore.firestore()
                        guard let userId = Auth.auth().currentUser?.uid else { return }
                        
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
                        
                        // Show the swiper immediately
                        await MainActor.run {
                            showingGeneratedVideos = true
                        }
                        
                        // Generate new videos using folder-specific generation
                        for try await videoId in VideoGenerator.shared.generateFolderVideosStream(
                            likedVideos: videosWithPrompts,
                            profile: profile
                        ) {
                            await MainActor.run {
                                self.generatedVideoIds.append(videoId)
                            }
                        }
                        
                        await MainActor.run {
                            self.isGenerating = false
                        }
                        return
                    } else {
                        // Wait a bit before retrying
                        try await Task.sleep(nanoseconds: UInt64(1_000_000_000 * Double(attempt + 1)))
                    }
                }
                
                // If we get here, we failed to get the profile after retries
                await MainActor.run {
                    self.profileLoadError = "Could not load user profile. Please try again."
                    self.isGenerating = false
                }
            } catch {
                print("Error generating videos: \(error)")
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
    @State private var isVisible = false  // Add this state variable
    
    private var currentVideoId: String? {
        guard currentIndex < generatedVideoIds.count else { return nil }
        let id = generatedVideoIds[currentIndex]
        print("📺 Current video ID: \(id) at index \(currentIndex)")
        return id
    }
    
    private var nextVideoId: String? {
        guard currentIndex + 1 < generatedVideoIds.count else { return nil }
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
        
        // Update player cache position for current video
        if let currentId = currentVideoId {
            PlayerCache.shared.updatePosition(current: currentId)
        }
        
        // Preload next videos
        for i in (index + 1)...maxIndex {
            let videoId = generatedVideoIds[i]
            // Skip if already preloaded
            if PlayerCache.shared.hasPlayer(for: videoId) { continue }
            
            // Start loading the video immediately
            VideoURLCache.shared.getVideoURL(for: videoId) { url in
                if let url = url {
                    VideoFileCache.shared.getLocalVideoURL(for: videoId, remoteURL: url) { localURL in
                        if let localURL = localURL {
                            print("✅ Preloaded video: \(videoId)")
                            
                            Task { @MainActor in
                                let player = AVPlayer(url: localURL)
                                player.automaticallyWaitsToMinimizeStalling = false
                                player.currentItem?.preferredForwardBufferDuration = 2
                                
                                // Add to cache immediately
                                PlayerCache.shared.setPlayer(player, for: videoId)
                                
                                // Wait for player to be ready
                                for _ in 0..<50 { // Try for 5 seconds
                                    if player.status == .readyToPlay {
                                        player.preroll(atRate: 1) { _ in
                                            print("🎮 Player prerolled for video: \(videoId)")
                                        }
                                        break
                                    }
                                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
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
            Color.black
                .opacity(isDismissing ? 0 : (isVisible ? 0.6 : 0))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.2), value: isDismissing)
                .animation(.easeInOut(duration: 0.2), value: isVisible)
            
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
                    .opacity(0.7)
                    .onAppear {
                        print("🎴 Rendering next card: \(nextId)")
                        // Ensure video is preloaded
                        preloadNextVideos(from: currentIndex)
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
                    .opacity(isDismissing ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: isDismissing)
                    .onAppear {
                        print("🎴 Rendering current card: \(videoId)")
                        // Reset animation state when new card appears
                        isAnimatingTransition = false
                        // Ensure next videos are preloaded
                        preloadNextVideos(from: currentIndex)
                    }
                    .allowsHitTesting(!isAnimatingTransition)  // Only disable hit testing during animation
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                guard !isAnimatingTransition else { return }  // Ignore gestures during animation
                                print("👆 Drag changed: \(gesture.translation.width)")
                                isSwiping = true
                                withAnimation(.interactiveSpring()) {
                                    offset = gesture.translation.width
                                }
                            }
                            .onEnded { gesture in
                                guard !isAnimatingTransition else { return }  // Ignore gestures during animation
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
                                        withAnimation(nil) {  // Disable animation for state updates
                                            currentIndex += 1
                                            offset = 0
                                        }
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
                        guard !isAnimatingTransition else { return }  // Ignore taps during animation
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
                            withAnimation(nil) {  // Disable animation for state updates
                                currentIndex += 1
                                offset = 0
                            }
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
                    Text("No more videos")
                        .foregroundColor(.secondary)
                        .padding(.top, 60)
                        .opacity(isDismissing ? 0 : 1)
                        .animation(.easeOut(duration: 0.2), value: isDismissing)
                }
            }
            .onChange(of: currentIndex) { newIndex in
                print("🔄 Current index changed to: \(newIndex)")
                print("📊 Total videos: \(generatedVideoIds.count)")
                
                // Clear player cache when index changes to force thumbnail reload
                if let oldId = currentVideoId {
                    PlayerCache.shared.removePlayer(for: oldId)
                }
                
                // Preload next videos when current index changes
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
            .padding(.top, 60)  // Move down from top
        }
        .presentationBackground(.clear)
        .onAppear {
            print("🎬 VideoSwiperView appeared")
            print("📊 Total videos: \(generatedVideoIds.count)")
            print("🎯 Starting index: \(currentIndex)")
            
            // Animate background in after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isVisible = true
            }
            
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