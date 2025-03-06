import SwiftUI
import FirebaseAuth
import AVKit
import FirebaseStorage
import FirebaseFirestore
import FirebaseVertexAI

struct ProfileView: View {
    // Define counter class here at the type level
    private class Counters {
        var success = 0
        var failure = 0
        var processed = 0
        var skipped = 0
    }
    
    let userName: String
    @ObservedObject var likesService: LikesService
    @StateObject private var bookmarksService = BookmarksService()
    @StateObject private var userVideoService = UserVideoService.shared
    @StateObject private var videoService = VideoService.shared
    @State private var selectedTab = 0
    @State private var isSeeding = false
    @State private var isClearing = false
    @State private var isAnalyzing = false
    @State private var analysisResult: String?
    @State private var showingAnalysis = false
    @Environment(\.dismiss) private var dismiss
    @State private var isDuplicating = false
    @State private var isCopying = false
    @State private var isUpdatingMetadata = false
    
    private var userPhotoURL: URL? {
        Auth.auth().currentUser?.photoURL
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Profile Header
                VStack(spacing: 20) {
                    // Avatar Image
                    CachedAvatarView(size: 90)
                    
                    // Username
                    Text(userName)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                // .padding(.top, 4)
                .padding(.bottom, 24)
                
                // Divider
                Divider()
                
                // Custom tab header
                HStack(spacing: 0) {
                    ForEach(["Likes", "Bookmarks", "Videos"].indices, id: \.self) { index in
                        Button(action: {
                            withAnimation {
                                selectedTab = index
                            }
                        }) {
                            VStack(spacing: 8) {
                                Text(["Likes", "Bookmarks", "Videos"][index])
                                    .foregroundColor(selectedTab == index ? .primary : .secondary)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .padding(.vertical, 12)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                // Tab content with page style using simplified GridView with defaults
                TabView(selection: $selectedTab) {
                    GridView<LikedVideo, LikedVideoPlayerView>(
                        videos: likesService.likedVideos,
                        fullscreenContent: { sortedVideos, selectedVideoId in
                            LikedVideoPlayerView(
                                likedVideos: sortedVideos,
                                initialIndex: sortedVideos.firstIndex(where: { $0.id == selectedVideoId }) ?? 0,
                                likesService: likesService
                            )
                        }
                    )
                    .tag(0)
                    
                    GridView<BookmarkedVideo, BookmarkedVideoPlayerView>(
                        videos: bookmarksService.bookmarkedVideos,
                        fullscreenContent: { sortedVideos, selectedVideoId in
                            BookmarkedVideoPlayerView(
                                bookmarkedVideos: sortedVideos,
                                initialIndex: sortedVideos.firstIndex(where: { $0.id == selectedVideoId }) ?? 0,
                                bookmarksService: bookmarksService
                            )
                        },
                        bookmarksService: bookmarksService
                    )
                    .tag(1)
                    
                    GridView<UserVideo, UserVideoPlayerView>(
                        videos: userVideoService.userVideos,
                        fullscreenContent: { sortedVideos, selectedVideoId in
                            UserVideoPlayerView(
                                userVideos: sortedVideos,
                                initialIndex: sortedVideos.firstIndex(where: { $0.id == selectedVideoId }) ?? 0
                            )
                        }
                    )
                    .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(.container, edges: .bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 16) {
                        Button(action: seedMetadata) {
                            if isSeeding {
                                ProgressView()
                                    .tint(.green)
                            } else {
                                Image(systemName: "leaf.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .disabled(isSeeding)
                        
                        Button(action: clearProfile) {
                            if isClearing {
                                ProgressView()
                                    .tint(.red)
                            } else {
                                Image(systemName: "trash.fill")
                                    .foregroundColor(.red.opacity(0.6))
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .disabled(isClearing)
                        
                        Button(action: analyzeProfile) {
                            if isAnalyzing {
                                ProgressView()
                                    .tint(.blue)
                            } else {
                                Image(systemName: "wand.and.stars")
                                    .foregroundColor(.blue.opacity(0.6))
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .disabled(isAnalyzing)

                        Button(action: deduplicateInterests) {
                            if isDuplicating {
                                ProgressView()
                                    .tint(.purple)
                            } else {
                                Image(systemName: "arrow.triangle.merge")
                                    .foregroundColor(.purple.opacity(0.6))
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .disabled(isDuplicating)
                        
                        Button(action: copyGeneratedVideos) {
                            if isCopying {
                                ProgressView()
                                    .tint(.orange)
                            } else {
                                Image(systemName: "doc.on.doc.fill")
                                    .foregroundColor(.orange.opacity(0.6))
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .disabled(isCopying)
                        
                        Button(action: updateCopiedVideosMetadata) {
                            if isUpdatingMetadata {
                                ProgressView()
                                    .tint(.cyan)
                            } else {
                                Image(systemName: "tag.fill")
                                    .foregroundColor(.cyan.opacity(0.6))
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .disabled(isUpdatingMetadata)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: signOut) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red.opacity(0.6))
                            .font(.system(size: 17, weight: .semibold))
                            .scaleEffect(x: -1, y: 1)
                    }
                }
            }
        }
        .task {
            await bookmarksService.loadBookmarkedVideos()
            await userVideoService.loadUserVideos()
        }
        .presentationBackground(.thinMaterial)
        .sheet(isPresented: $showingAnalysis) {
            NavigationView {
                ScrollView {
                    Text(analysisResult ?? "")
                        .padding()
                }
                .navigationTitle("Image Analysis")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showingAnalysis = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
    
    private func signOut() {
        do {
            try Auth.auth().signOut()
            dismiss()
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
    
    private func seedMetadata() {
        Task {
            isSeeding = true
            let storage = Storage.storage()
            let seedRef = storage.reference().child("videos/seed")
            
            let videoPrompts: [String: String] = [
                "dog": "A close-up portrait of a Golden Retriever puppy with fluffy fur bathed in soft morning light. The puppy's eyes sparkle with playful joy, and its pink tongue peeks out in an adorable blep. Shot with a shallow depth of field, creating a dreamy, blurred background of pastel greens and golds. Professional photography with warm color grading emphasizes the honey-colored fur and captures fine details like whiskers and the texture of its velvet nose. The image has a cozy, heartwarming mood that highlights the puppy's natural charm.",
                "patriot": "A majestic American flag billowing against a dramatic sunset sky, its fabric catching golden light as it waves in the mountain breeze. The flag's stars and stripes are captured in pristine detail, showing subtle textile textures and natural folds. Behind it, rays of sunlight pierce through scattered clouds, creating a rich palette of deep reds, warm oranges, and royal blues. Shot in high resolution with professional equipment, emphasizing both the grand scale and intimate details of the scene. The composition creates a sense of timeless dignity, with the flag positioned against a backdrop of distant purple mountains and amber-lit clouds.",
                "anime": "A stylized anime warrior standing in a cherry blossom storm, their long hair and flowing traditional robes dancing in the wind. The scene features vibrant cel-shaded artwork with dramatic lighting, sharp line art, and a soft bokeh effect from the pink petals. The character design shows intricate armor details with a mix of traditional Japanese elements and fantasy elements. Background features a misty mountain temple with golden hour lighting creating a cinematic atmosphere.",
                "submarine": "A submarine control room bathed in the red glow of emergency lighting. The sonar operator's face is illuminated by multiple blue-tinted screens showing underwater topography and contact signatures. Their specialized headset and tactical gear stand out against the background of complex instrumentation and classified system readouts.",
                "alien": "A classified underground laboratory illuminated by stark surgical lights, where technicians in hazmat suits work at a sterile steel table. Their protective gear features advanced monitoring equipment and reflective patches catching the light. The specimen table displays holographic medical readouts and contains an otherworldly figure partially obscured by specialized containment equipment. The scene is captured through security camera-style framing with government classification markers in the corners. Multiple screens in the background show DNA sequences and exotic biological readings in neon green and blue, while warning lights cast an eerie red glow across the metallic surfaces. The atmosphere is clinical yet mysterious, with subtle steam venting from cryogenic equipment adding depth to the shadowy facility."
            ]
            
            do {
                let result = try await seedRef.listAll()
                
                for item in result.items {
                    let videoName = String(item.name.dropLast(4)) // Remove .mp4
                    print("🔍 Processing video: \(item.fullPath)")
                    
                    if let prompt = videoPrompts[videoName] {
                        do {
                            let metadata = StorageMetadata()
                            metadata.customMetadata = ["prompt": prompt]
                            
                            _ = try await item.updateMetadata(metadata)
                            print("✅ Set metadata for video: \(videoName)")
                        } catch {
                            print("❌ Error with \(videoName): \(error)")
                        }
                    }
                }
                
                print("📹 Finished setting metadata for seed videos")
            } catch {
                print("❌ Error setting video metadata: \(error)")
            }
            
            isSeeding = false
        }
    }
    
    private func clearProfile() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            isClearing = true
            let db = Firestore.firestore()
            let storage = Storage.storage()
            
            do {
                // Create a batch to perform all operations atomically
                let batch = db.batch()
                
                // Clear interests collection
                let interestsSnapshot = try await db.collection("users")
                    .document(userId)
                    .collection("interests")
                    .getDocuments()
                
                for doc in interestsSnapshot.documents {
                    batch.deleteDocument(doc.reference)
                }
                
                // Reset user document
                let userRef = db.collection("users").document(userId)
                batch.updateData([
                    "description": "",
                    "lastUpdated": FieldValue.delete()
                ], forDocument: userRef)
                
                // Reset watch counts
                let watchCountsRef = userRef.collection("watchCounts").document("counts")
                batch.setData([
                    "videosWatchedSinceLastPrompt": 0,
                    "videosWatchedSinceLastProfile": 0
                ], forDocument: watchCountsRef, merge: true)
                
                // Separately remove the timestamp fields using updateData
                batch.updateData([
                    "lastPromptGeneration": FieldValue.delete(),
                    "lastProfileUpdate": FieldValue.delete()
                ], forDocument: watchCountsRef)
                
                // Clear video interactions
                let interactionsSnapshot = try await db.collection("users")
                    .document(userId)
                    .collection("videoInteractions")
                    .getDocuments()
                
                for doc in interactionsSnapshot.documents {
                    batch.deleteDocument(doc.reference)
                }
                
                // Clear bookmarks collection
                let bookmarksSnapshot = try await db.collection("users")
                    .document(userId)
                    .collection("bookmarks")
                    .getDocuments()
                
                for doc in bookmarksSnapshot.documents {
                    batch.deleteDocument(doc.reference)
                }
                
                // Clear bookmark folders collection
                let bookmarkFoldersSnapshot = try await db.collection("users")
                    .document(userId)
                    .collection("bookmarkFolders")
                    .getDocuments()
                
                for doc in bookmarkFoldersSnapshot.documents {
                    batch.deleteDocument(doc.reference)
                }
                
                // Commit all Firestore changes
                try await batch.commit()
                
                // Delete all generated videos
                let generatedRef = storage.reference().child("videos/generated")
                let generatedVideos = try await generatedRef.listAll()
                
                for item in generatedVideos.items {
                    try await item.delete()
                    print("✅ Deleted generated video: \(item.name)")
                }
                
                print("✅ Successfully cleared user profile data and generated videos")
                
            } catch {
                print("❌ Error clearing profile: \(error)")
            }
            
            isClearing = false
        }
    }
    
    private func analyzeProfile() {
        Task {
            isAnalyzing = true
            do {
                // Make sure liked videos are loaded
                await likesService.loadLikedVideos()
                
                // Get five most recent liked videos
                let sortedVideos = likesService.likedVideos.sorted { $0.timestamp > $1.timestamp }
                let recentVideos = Array(sortedVideos.prefix(5))
                
                if recentVideos.count > 0 {
                    var thumbnailImages: [(label: String, image: UIImage?)] = []
                    
                    // Get thumbnails for all videos
                    for (index, video) in recentVideos.enumerated() {
                        // Get the thumbnail using the async version
                        _ = await ThumbnailGenerator.getThumbnail(for: video.id)
                        if let uiImage = ThumbnailCache.shared.getCachedUIImageThumbnail(for: video.id) {
                            thumbnailImages.append(("Image \(index + 1)", uiImage))
                        }
                    }
                    
                    // Filter out any nil images and prepare for analysis
                    let validImages = thumbnailImages.compactMap { label, image -> (label: String, image: UIImage)? in
                        if let image = image {
                            return (label: label, image: image)
                        }
                        return nil
                    }
                    
                    if !validImages.isEmpty {
                        let descriptions = validImages.map { "describe \($0.label)" }.joined(separator: ", then ")
                        let result = try await VertexAIService.shared.generateContentForFive(
                            images: validImages,
                            prompt: descriptions
                        )
                        analysisResult = result
                    } else {
                        analysisResult = "Could not load any thumbnails for the recent liked videos"
                    }
                } else {
                    analysisResult = "No liked videos found"
                }
                showingAnalysis = true
            } catch {
                print("❌ Error analyzing images: \(error)")
                analysisResult = "Error: \(error.localizedDescription)"
                showingAnalysis = true
            }
            isAnalyzing = false
        }
    }
    
    private func deduplicateInterests() {
        Task {
            isDuplicating = true
            defer { isDuplicating = false }
            
            guard let profile = await ProfileService.shared.currentProfile else {
                return
            }
            
            guard let userId = Auth.auth().currentUser?.uid else {
                print("❌ Error deduplicating: User not authenticated")
                return
            }
            
            // Log the number of interests before cleanup
            print("📊 Before deduplication: \(profile.interests.count) interests")
            
            // Create a dictionary to store unique interests by topic
            var uniqueInterests: [String: Interest] = [:]
            
            // Process each interest
            for interest in profile.interests {
                if let existing = uniqueInterests[interest.topic] {
                    // Merge examples and take the higher weight
                    var merged = Interest(topic: interest.topic, examples: Array(Set(existing.examples + interest.examples)))
                    merged.weight = max(existing.weight, interest.weight)
                    uniqueInterests[interest.topic] = merged
                } else {
                    uniqueInterests[interest.topic] = interest
                }
            }
            
            // Create new profile with deduplicated interests
            let newProfile = UserProfile(
                interests: Array(uniqueInterests.values),
                description: profile.description
            )
            
            // Log the number of interests after cleanup
            print("🧹 After deduplication: \(uniqueInterests.count) interests")
            
            // Store the updated profile
            do {
                let db = Firestore.firestore()
                
                // First, delete all existing interests
                print("🗑️ Deleting all existing interests...")
                let interestsSnapshot = try await db.collection("users")
                    .document(userId)
                    .collection("interests")
                    .getDocuments()
                
                // Create a batch to delete all existing interests
                let deleteBatch = db.batch()
                for doc in interestsSnapshot.documents {
                    deleteBatch.deleteDocument(doc.reference)
                }
                
                // Commit the delete batch
                try await deleteBatch.commit()
                print("✅ Deleted all existing interests")
                
                // Now store the new deduplicated profile
                try await ProfileService.shared.storeProfile(newProfile)
                print("✅ Successfully deduplicated interests")
            } catch {
                print("❌ Error deduplicating interests: \(error)")
            }
        }
    }
    
    private func copyGeneratedVideos() {
        isCopying = true
        let storage = Storage.storage()
        let generatedRef = storage.reference().child("videos/generated")
        let targetFolderRef = storage.reference().child("videos/generated/FRsSuRVvSDNDJeLiiWao57W2jjl1")
            
        // List all files in the generated videos folder
        generatedRef.listAll { result, error in
            if let error = error {
                print("❌ Error listing files: \(error)")
                self.isCopying = false
                return
            }
            
            guard let result = result else {
                print("❌ Error: Result is nil")
                self.isCopying = false
                return
            }
            
            print("🔍 Found \(result.items.count) videos to copy")
            
            // Use the class defined at the type level
            let counters = Counters()
            
            // If no files to process, we're done
            if result.items.isEmpty {
                print("🎉 No files to copy")
                self.isCopying = false
                return
            }
            
            // Function to check if we're done processing
            let checkIfDone = {
                if counters.processed >= result.items.count {
                    print("🎉 Copy operation completed: \(counters.success) successful, \(counters.failure) failed")
                    self.isCopying = false
                }
            }
            
            // Process each file
            for (index, item) in result.items.enumerated() {
                if !item.name.hasSuffix(".mp4") {
                    print("⏭️ Skipping non-MP4 file: \(item.name)")
                    counters.processed += 1
                    checkIfDone()
                    continue
                }
                
                let targetRef = targetFolderRef.child(item.name)
                
                // First, get metadata so we can include it in the upload
                item.getMetadata { metadata, metadataError in
                    if let metadataError = metadataError {
                        print("⚠️ Failed to get metadata for \(item.name): \(metadataError)")
                        // Continue without metadata
                        self.downloadAndUploadFile(item: item, targetRef: targetRef, index: index, totalCount: result.items.count, metadata: nil, counters: counters, checkIfDone: checkIfDone)
                        return
                    }
                    
                    // Download and upload with metadata included
                    self.downloadAndUploadFile(item: item, targetRef: targetRef, index: index, totalCount: result.items.count, metadata: metadata, counters: counters, checkIfDone: checkIfDone)
                }
            }
        }
    }
    
    // Helper method to download and upload a file with optional metadata
    private func downloadAndUploadFile(
        item: StorageReference,
        targetRef: StorageReference,
        index: Int,
        totalCount: Int,
        metadata: StorageMetadata?,
        counters: AnyObject,
        checkIfDone: @escaping () -> Void
    ) {
        guard let counters = counters as? Counters else { return }
        
        // Download the file data
        item.getData(maxSize: 50 * 1024 * 1024) { data, error in
            if let error = error {
                print("❌ Failed to download \(item.name): \(error)")
                counters.failure += 1
                counters.processed += 1
                checkIfDone()
                return
            }
            
            guard let data = data else {
                print("❌ Failed to download \(item.name): Data is nil")
                counters.failure += 1
                counters.processed += 1
                checkIfDone()
                return
            }
            
            // Upload the data to the target location with metadata included
            targetRef.putData(data, metadata: metadata) { _, uploadError in
                if let uploadError = uploadError {
                    print("❌ Failed to upload \(item.name): \(uploadError)")
                    counters.failure += 1
                } else {
                    counters.success += 1
                    print("✅ Copied file \(index+1)/\(totalCount): \(item.name)\(metadata == nil ? " (without metadata)" : "")")
                }
                
                counters.processed += 1
                checkIfDone()
            }
        }
    }
    
    // Function to update only the metadata for already copied videos
    private func updateCopiedVideosMetadata() {
        isUpdatingMetadata = true
        let storage = Storage.storage()
        let generatedRef = storage.reference().child("videos/generated")
        let targetFolderRef = storage.reference().child("videos/generated/FRsSuRVvSDNDJeLiiWao57W2jjl1")
            
        // List all files in the source folder
        generatedRef.listAll { result, error in
            if let error = error {
                print("❌ Error listing source files: \(error)")
                self.isUpdatingMetadata = false
                return
            }
            
            guard let result = result else {
                print("❌ Error: Source result is nil")
                self.isUpdatingMetadata = false
                return
            }
            
            // List all files in the target folder
            targetFolderRef.listAll { targetResult, targetError in
                if let targetError = targetError {
                    print("❌ Error listing target files: \(targetError)")
                    self.isUpdatingMetadata = false
                    return
                }
                
                guard let targetResult = targetResult else {
                    print("❌ Error: Target result is nil")
                    self.isUpdatingMetadata = false
                    return
                }
                
                // Convert target files to a dictionary for quick lookup
                let targetFiles = Dictionary(uniqueKeysWithValues: targetResult.items.map { ($0.name, $0) })
                
                print("🔍 Found \(result.items.count) source videos and \(targetFiles.count) target videos")
                
                // Use the class defined at the type level 
                let counters = Counters()
                
                // Function to check if we're done processing
                let checkIfDone = {
                    if counters.processed >= result.items.count {
                        print("🎉 Metadata update completed: \(counters.success) successful, \(counters.failure) failed, \(counters.skipped) skipped")
                        self.isUpdatingMetadata = false
                    }
                }
                
                // If no files to process, we're done
                if result.items.isEmpty {
                    print("🎉 No files to process")
                    self.isUpdatingMetadata = false
                    return
                }
                
                // Process each source file
                for (index, item) in result.items.enumerated() {
                    if !item.name.hasSuffix(".mp4") {
                        print("⏭️ Skipping non-MP4 file: \(item.name)")
                        counters.processed += 1
                        counters.skipped += 1
                        checkIfDone()
                        continue
                    }
                    
                    // Find target file
                    guard let targetRef = targetFiles[item.name] else {
                        print("⏭️ Skipping \(item.name) - not found in target folder")
                        counters.processed += 1
                        counters.skipped += 1
                        checkIfDone()
                        continue
                    }
                    
                    // Get source metadata
                    item.getMetadata { metadata, metadataError in
                        if let metadataError = metadataError {
                            print("⚠️ Failed to get metadata for \(item.name): \(metadataError)")
                            counters.failure += 1
                            counters.processed += 1
                            checkIfDone()
                            return
                        }
                        
                        guard let metadata = metadata else {
                            print("⚠️ No metadata found for \(item.name)")
                            counters.failure += 1
                            counters.processed += 1
                            checkIfDone()
                            return
                        }
                        
                        // Log metadata contents
                        print("📋 Source metadata for \(item.name):")
                        if let customMetadata = metadata.customMetadata, !customMetadata.isEmpty {
                            for (key, value) in customMetadata {
                                print("    - \(key): \(value.prefix(50))...")
                            }
                        } else {
                            print("    - No custom metadata found")
                        }
                        
                        // Create a new metadata object instead of trying to update the existing one
                        let newMetadata = StorageMetadata()
                        newMetadata.customMetadata = metadata.customMetadata
                        
                        // Update target metadata with the new metadata object
                        targetRef.updateMetadata(newMetadata) { updatedMetadata, updateError in
                            if let updateError = updateError {
                                print("❌ Failed to update metadata for \(item.name): \(updateError)")
                                counters.failure += 1
                            } else {
                                counters.success += 1
                                print("✅ Updated metadata for file \(index+1)/\(result.items.count): \(item.name)")
                                
                                // Verify metadata was actually updated by getting it again
                                targetRef.getMetadata { verifiedMetadata, verifyError in
                                    if let verifyError = verifyError {
                                        print("⚠️ Couldn't verify metadata for \(item.name): \(verifyError)")
                                    } else if let verifiedMetadata = verifiedMetadata {
                                        print("🔍 Verified target metadata for \(item.name):")
                                        if let customMetadata = verifiedMetadata.customMetadata, !customMetadata.isEmpty {
                                            for (key, value) in customMetadata {
                                                print("    - \(key): \(value.prefix(50))...")
                                            }
                                        } else {
                                            print("    - No custom metadata found after update")
                                        }
                                    }
                                }
                            }
                            
                            counters.processed += 1
                            checkIfDone()
                        }
                    }
                }
            }
        }
    }
}

// Model to hold a static snapshot of videos for the player

extension Image {
    func asUIImage() -> UIImage? {
        let controller = UIHostingController(rootView: self)
        let view = controller.view
        
        let targetSize = controller.view.intrinsicContentSize
        view?.bounds = CGRect(origin: .zero, size: targetSize)
        view?.backgroundColor = .clear
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            view?.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}
 