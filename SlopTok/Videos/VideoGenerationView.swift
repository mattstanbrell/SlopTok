import SwiftUI
import FirebaseStorage
import FirebaseAuth

struct VideoGenerationView: View {
    @Environment(\.dismiss) private var dismiss
    let videoId: String
    @ObservedObject var likesService: LikesService
    @ObservedObject var bookmarksService: BookmarksService
    
    @State private var isGenerating = false
    @State private var error: String?
    @State private var generatedVideoId: String?
    @State private var showError = false
    @State private var offset: CGFloat = 0
    @State private var isSwiping = false
    @State private var isAnimatingTransition = false
    @State private var isDismissing = false
    
    private let storage = Storage.storage()
    private let cloudflareWorkerUrl = "https://sloptok-luma.mattstanbrell.workers.dev"
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if isGenerating {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                    Text("Generating video...")
                        .foregroundColor(.white)
                }
            } else if let error = error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if let videoId = generatedVideoId {
                VideoPlayerView(
                    videoResource: videoId,
                    likesService: likesService,
                    isVideoLiked: .constant(false)
                )
                .offset(x: offset)
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
                                
                                // Save if swiped right
                                if direction {
                                    print("💾 Saving video: \(videoId)")
                                    saveVideo(videoId)
                                }
                                
                                print("🎬 Starting swipe animation")
                                isAnimatingTransition = true
                                
                                // Animate the card off screen
                                withAnimation(.spring()) {
                                    offset = direction ? width : -width
                                }
                                
                                // Dismiss after animation
                                print("⏰ Scheduling dismiss")
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    isDismissing = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        dismiss()
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
                    // Double tap to save
                    print("💾 Saving video: \(videoId)")
                    saveVideo(videoId)
                    
                    print("🎬 Starting swipe animation")
                    isAnimatingTransition = true
                    
                    // Animate the card off screen
                    withAnimation(.spring()) {
                        offset = UIScreen.main.bounds.width
                    }
                    
                    // Dismiss after animation
                    print("⏰ Scheduling dismiss")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isDismissing = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            dismiss()
                        }
                    }
                }
            }
            
            // Swipe indicators
            if let _ = generatedVideoId {
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
        }
        .presentationBackground(.clear)
        .task {
            await generateVideo()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(error ?? "An unknown error occurred")
        }
    }
    
    private func generateVideo() async {
        isGenerating = true
        error = nil
        
        do {
            // Get thumbnail to use as start image
            guard let thumbnail = await VideoService.shared.getUIImageThumbnail(for: videoId),
                  let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get thumbnail"])
            }
            
            // Upload thumbnail to temporary storage to get URL
            let tempImageRef = storage.reference().child("videos/temp/\(UUID().uuidString).jpg")
            print("📤 Uploading to path: \(tempImageRef.fullPath)")
            
            // Add metadata to ensure content type is set
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            print("📝 Setting metadata: contentType=\(metadata.contentType ?? "nil")")
            
            print("⏳ Starting upload...")
            _ = try await tempImageRef.putDataAsync(thumbnailData, metadata: metadata)
            print("✅ Upload completed")
            
            // Add retry mechanism for getting download URL
            var startImageUrl: URL?
            for attempt in 1...3 {
                do {
                    print("🔄 Attempt \(attempt): Getting download URL...")
                    try await Task.sleep(nanoseconds: UInt64(0.5 * Double(attempt) * Double(NSEC_PER_SEC)))
                    startImageUrl = try await tempImageRef.downloadURL()
                    print("✅ Got download URL: \(startImageUrl?.absoluteString ?? "nil")")
                    break
                } catch {
                    print("❌ Attempt \(attempt) failed: \(error.localizedDescription)")
                    if let nsError = error as? NSError {
                        print("Error details - Domain: \(nsError.domain), Code: \(nsError.code)")
                        if let errorData = nsError.userInfo["data"] as? Data,
                           let errorString = String(data: errorData, encoding: .utf8) {
                            print("Error data: \(errorString)")
                        }
                    }
                    if attempt == 3 {
                        throw error
                    }
                    print("⏳ Waiting before next attempt...")
                }
            }
            
            guard let startImageUrl = startImageUrl else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get download URL after retries"])
            }
            
            // Get the prompt from the original video's metadata
            let videoRef = storage.reference().child(VideoService.shared.getVideoPath(videoId))
            print("🎥 Getting metadata for video: \(videoRef.fullPath)")
            let videoMetadata = try await videoRef.getMetadata()
            print("📝 Video metadata: \(videoMetadata.customMetadata ?? [:])")
            guard let prompt = videoMetadata.customMetadata?["prompt"] else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No prompt found for video"])
            }
            print("✍️ Using prompt: \(prompt)")
            
            // Call the worker to generate the video
            let workerUrl = URL(string: cloudflareWorkerUrl)!
            print("🌐 Calling worker at: \(cloudflareWorkerUrl)")
            var request = URLRequest(url: workerUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("*", forHTTPHeaderField: "Access-Control-Allow-Origin")
            
            let requestBody = [
                "prompt": prompt,
                "startImageUrl": startImageUrl.absoluteString
            ]
            print("📦 Request body: \(requestBody)")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            print("⏳ Making API request...")
            let (data, response) = try await URLSession.shared.data(for: request)
            print("✅ Got API response")
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Response data: \(responseString)")
            }
            
            // Clean up temporary image
            try? await tempImageRef.delete()
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            guard httpResponse.statusCode == 200 else {
                throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error"])
            }
            
            let generationResponse = try JSONDecoder().decode(GenerationResponse.self, from: data)
            
            if !generationResponse.success {
                throw NSError(domain: "", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: generationResponse.error ?? "Generation failed"
                ])
            }
            
            guard let videoUrl = generationResponse.videoUrl,
                  let url = URL(string: videoUrl) else {
                throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video URL in response"])
            }
            
            // Download the video
            let (videoData, _) = try await URLSession.shared.data(from: url)
            
            // Generate video ID and upload to Firebase
            let timestamp = String(format: "%06x", Int(Date().timeIntervalSince1970) % 0xFFFFFF)
            let randomChars = "abcdefghijklmnopqrstuvwxyz0123456789"
            let random = String((0..<4).map { _ in randomChars.randomElement()! })
            let newVideoId = "\(timestamp)\(random)"
            
            // Upload to Firebase Storage
            let newVideoRef = storage.reference().child("videos/generated/\(newVideoId).mp4")
            let finalVideoMetadata = StorageMetadata()
            finalVideoMetadata.contentType = "video/mp4"
            finalVideoMetadata.customMetadata = [
                "prompt": prompt,
                "parentIds": videoId
            ]
            
            _ = try await newVideoRef.putDataAsync(videoData, metadata: finalVideoMetadata)
            
            await MainActor.run {
                self.generatedVideoId = newVideoId
                self.isGenerating = false
            }
            
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.showError = true
                self.isGenerating = false
            }
        }
    }
    
    private func saveVideo(_ videoId: String) {
        Task {
            await UserVideoService.shared.addVideo(videoId)
        }
    }
} 