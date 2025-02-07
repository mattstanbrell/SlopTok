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
                    GridView(videos: likesService.likedVideos) { sortedVideos, selectedVideoId in
                        LikedVideoPlayerView(
                            likedVideos: sortedVideos,
                            initialIndex: sortedVideos.firstIndex(where: { $0.id == selectedVideoId }) ?? 0,
                            likesService: likesService
                        )
                    }
                    .tag(0)
                    
                    GridView(videos: bookmarksService.bookmarkedVideos) { sortedVideos, selectedVideoId in
                        BookmarkedVideoPlayerView(
                            bookmarkedVideos: sortedVideos,
                            initialIndex: sortedVideos.firstIndex(where: { $0.id == selectedVideoId }) ?? 0,
                            bookmarksService: bookmarksService
                        )
                    }
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
                            .foregroundColor(.red.opacity(0.6))
                            .font(.system(size: 17, weight: .semibold))
                            .scaleEffect(x: -1, y: 1)
                    }
                }
            }
        }
        .task {
            await bookmarksService.loadBookmarkedVideos()
        }
        .presentationBackground(.thinMaterial)
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
 