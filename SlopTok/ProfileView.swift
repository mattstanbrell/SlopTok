import SwiftUI
import FirebaseAuth
import AVKit
import FirebaseStorage

struct ProfileView: View {
    let userName: String
    @ObservedObject var likesService: LikesService
    @StateObject private var bookmarksService = BookmarksService()
    @State private var selectedTab = 0
    @Environment(\.dismiss) private var dismiss
    
    private var userPhotoURL: URL? {
        Auth.auth().currentUser?.photoURL
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Profile Header
                VStack(spacing: 20) {
                    // Avatar Image
                    AsyncImage(url: userPhotoURL) { phase in
                        switch phase {
                        case .empty:
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 90, height: 90)
                                .overlay {
                                    ProgressView()
                                }
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 90, height: 90)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        case .failure(_):
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 90, height: 90)
                                .foregroundColor(.gray)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .shadow(radius: 2)
                    
                    // Username
                    Text(userName)
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
                
                // Divider
                Divider()
                
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
                            .padding(.vertical, 12)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Tab content with page style
                TabView(selection: $selectedTab) {
                    LikesGridView(likesService: likesService)
                        .tag(0)
                    
                    BookmarksGridView(bookmarksService: bookmarksService)
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: signOut) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
        }
        .task {
            await bookmarksService.loadBookmarkedVideos()
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
    let selectedVideoId: String
}

struct LikesGridView: View {
    @ObservedObject var likesService: LikesService
    @State private var thumbnails: [String: UIImage] = [:]
    @State private var selectedVideoIndex: Int? = nil
    @State private var videoPlayerSelection: VideoSelection? = nil
    
    // Updated grid layout with spacing
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(likesService.likedVideos.enumerated()), id: \.element.id) { index, video in
                    VideoThumbnail(videoId: video.id, thumbnail: thumbnails[video.id])
                        .onAppear {
                            generateThumbnail(for: video.id)
                        }
                        .onTapGesture {
                            let sortedVideos = likesService.likedVideos.sorted(by: { $0.timestamp > $1.timestamp })
                            videoPlayerSelection = VideoSelection(
                                videos: sortedVideos,
                                selectedVideoId: video.id
                            )
                        }
                }
            }
            .padding(2) // Add padding around the entire grid
        }
        .fullScreenCover(item: $videoPlayerSelection) { selection in
            if let index = selection.videos.firstIndex(where: { $0.id == selection.selectedVideoId }) {
                LikedVideoPlayerView(
                    likedVideos: selection.videos,
                    initialIndex: index,
                    likesService: likesService
                )
            } else {
                LikedVideoPlayerView(
                    likedVideos: selection.videos,
                    initialIndex: 0,
                    likesService: likesService
                )
            }
        }
    }
    
    private func generateThumbnail(for videoId: String) {
        if thumbnails[videoId] != nil { return }
        ThumbnailGenerator.generateThumbnail(for: videoId) { image in
            if let image = image {
                DispatchQueue.main.async {
                    thumbnails[videoId] = image
                }
            }
        }
    }
}
