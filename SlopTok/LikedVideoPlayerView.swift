import SwiftUI
import AVKit
import FirebaseAuth
import FirebaseFirestore

struct LikedVideoPlayerView: View {
    // Initial data passed in
    let initialVideos: [LikedVideo]
    let initialIndex: Int
    let likesService: LikesService
    @Environment(\.dismiss) private var dismiss
    
    // Local state
    @State private var currentVideos: [LikedVideo]
    @State private var scrollPosition: Int?
    @State private var isDotExpanded = false
    
    init(likedVideos: [LikedVideo], initialIndex: Int, likesService: LikesService) {
        self.initialVideos = likedVideos
        self.initialIndex = initialIndex
        self.likesService = likesService
        _currentVideos = State(initialValue: likedVideos)
        _scrollPosition = State(initialValue: initialIndex)
    }
    
    var userName: String {
        Auth.auth().currentUser?.displayName ?? "User"
    }
    
    var body: some View {
        Group {
            if currentVideos.isEmpty {
                Color.clear.onAppear {
                    dismiss()
                }
            } else {
                mainView
            }
        }
    }
    
    private var mainView: some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(currentVideos.enumerated()), id: \.element.id) { index, video in
                        ZStack {
                            LoopingVideoView(
                                videoResource: video.id,
                                likesService: likesService,
                                isVideoLiked: Binding(
                                    get: { currentVideos.contains(where: { $0.id == video.id }) },
                                    set: { _ in handleUnlike(at: index) }
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
            
            ControlDotView(
                isExpanded: $isDotExpanded,
                userName: userName,
                dotColor: .red,
                likesService: likesService
            )
            .padding(.top, 0)
            .frame(maxWidth: .infinity, alignment: .center)
            .zIndex(2)
        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    if gesture.translation.width > 100 {
                        dismiss()
                    }
                }
        )
    }
    
    private func handleUnlike(at index: Int) {
        guard index < currentVideos.count else { return }
        let videoToUnlike = currentVideos[index]
        let currentPosition = scrollPosition ?? 0
        
        // Update Firestore first
        likesService.toggleLike(videoId: videoToUnlike.id)
        
        // Then handle local state updates
        withAnimation {
            // Remove the video
            currentVideos.remove(at: index)
            
            if currentVideos.isEmpty {
                // If no videos left, dismiss
                dismiss()
            } else {
                // Adjust scroll position based on where we are
                if currentVideos.count == 1 {
                    // If only one video left, force scroll to it
                    scrollPosition = 0
                } else if index < currentPosition {
                    // If we removed a video above current position,
                    // adjust position to account for removed video
                    scrollPosition = currentPosition - 1
                } else if index == currentPosition {
                    // If we removed current video and there are more below,
                    // stay at same position to show next video
                    if index == currentVideos.count {
                        // Unless we're at the end, then scroll up
                        scrollPosition = currentVideos.count - 1
                    }
                }
                // If we removed a video below current position,
                // no need to adjust scroll position
            }
        }
    }
}

// Model to represent a liked video with timestamp
struct LikedVideo: Identifiable, Equatable {
    let id: String
    let timestamp: Date
    
    static func == (lhs: LikedVideo, rhs: LikedVideo) -> Bool {
        lhs.id == rhs.id
    }
}
