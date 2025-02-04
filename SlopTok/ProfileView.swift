import SwiftUI
import FirebaseAuth
import AVKit

struct ProfileView: View {
    let userName: String
    @ObservedObject var likesService: LikesService
    @State private var selectedTab = 0
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom tab header
                HStack(spacing: 0) {
                    ForEach(["Likes", "Bookmarks"].indices, id: \.self) { index in
                        Button(action: {
                            withAnimation {
                                selectedTab = index
                            }
                        }) {
                            VStack(spacing: 8) {
                                Text(["Likes", "Bookmarks"][index])
                                    .foregroundColor(selectedTab == index ? .primary : .secondary)
                                    .font(.system(size: 16, weight: .semibold))
                                
                                // Underline indicator
                                Rectangle()
                                    .fill(selectedTab == index ? Color.primary : Color.clear)
                                    .frame(height: 1)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                
                // Tab content with page style
                TabView(selection: $selectedTab) {
                    LikesGridView(likesService: likesService)
                        .tag(0)
                    
                    BookmarksView()
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle(userName)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: signOut) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.primary)
                    }
                }
            }
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
}

// Model to hold a static snapshot of videos for the player
struct VideoSelection: Identifiable {
    let id = UUID()
    let videos: [LikedVideo]
    let index: Int
}

struct LikesGridView: View {
    @ObservedObject var likesService: LikesService
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selectedVideoIndex: Int? = nil
    @State private var videoPlayerSelection: VideoSelection? = nil  // NEW: Separate state for player
    
    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(likesService.likedVideos.enumerated()), id: \.element.id) { index, video in
                    VideoThumbnail(videoId: video.id, thumbnail: thumbnails[video.id])
                        .onAppear {
                            generateThumbnail(for: video.id)
                        }
                        .onTapGesture {
                            // Create VideoSelection once when tapped
                            videoPlayerSelection = VideoSelection(
                                videos: Array(likesService.likedVideos),
                                index: index
                            )
                        }
                }
            }
        }
        .fullScreenCover(item: $videoPlayerSelection) { selection in
            LikedVideoPlayerView(
                likedVideos: selection.videos,
                initialIndex: selection.index,
                likesService: likesService
            )
        }
    }
    
    private func generateThumbnail(for videoId: String) {
        guard thumbnails[videoId] == nil,
              let videoURL = Bundle.main.url(forResource: videoId, withExtension: "mp4") else {
            return
        }
        
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 60), actualTime: nil)
            let thumbnail = UIImage(cgImage: cgImage)
            thumbnails[videoId] = thumbnail
        } catch {
            print("Error generating thumbnail: \(error.localizedDescription)")
        }
    }
}

struct VideoThumbnail: View {
    let videoId: String
    let thumbnail: UIImage?
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(1, contentMode: .fill)
            }
        }
    }
}

struct BookmarksView: View {
    var body: some View {
        VStack {
            Text("Bookmarks coming soon!")
                .foregroundColor(.gray)
        }
    }
}
