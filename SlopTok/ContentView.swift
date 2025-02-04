import SwiftUI
import AVKit
import FirebaseAuth

struct ContentView: View {
    let videos = ["man", "skyline", "water"]
    @State private var isDotExpanded = false
    @State private var scrollPosition: Int?
    @StateObject private var likesService = LikesService()
    @State private var currentVideoLiked = false
    
    var userName: String {
        Auth.auth().currentUser?.displayName ?? "User"
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
    
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(videos.enumerated()), id: \.offset) { index, video in
                        ZStack {
                            LoopingVideoView(
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
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .ignoresSafeArea()
            .scrollPosition(id: $scrollPosition)
            .onChange(of: scrollPosition) { newPosition in
                updateCurrentVideoLikedStatus()
                
                if isDotExpanded {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isDotExpanded = false
                    }
                }
            }
            .onReceive(likesService.$likedVideos) { _ in
                if scrollPosition == nil {
                    // Force check of initial video when likes first load
                    scrollPosition = 0
                }
                updateCurrentVideoLikedStatus()
            }
            .task {
                // Make sure likes are loaded when view appears
                await likesService.loadLikedVideos()
                updateCurrentVideoLikedStatus()
            }
            .zIndex(0)
            
            ControlDotView(
                isExpanded: $isDotExpanded,
                userName: userName,
                dotColor: currentVideoLiked ? .red : .white,
                likesService: likesService
            )
            .padding(.top, 0)
            .frame(maxWidth: .infinity, alignment: .center)
            .zIndex(2)
        }
    }
}
