import SwiftUI
import FirebaseAuth
import AVKit

struct ProfileView: View {
    let userName: String
    @ObservedObject var likesService: LikesService
    @State private var selectedTab = 0
    
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
        }
    }
}

struct LikesGridView: View {
    @ObservedObject var likesService: LikesService
    @State private var thumbnails: [String: UIImage] = [:]
    
    let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(likesService.likedVideos).sorted(), id: \.self) { videoId in
                    VideoThumbnail(videoId: videoId, thumbnail: thumbnails[videoId])
                        .onAppear {
                            generateThumbnail(for: videoId)
                        }
                }
            }
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
