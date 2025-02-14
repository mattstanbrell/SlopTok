import SwiftUI
import FirebaseAuth

protocol VideoIdentifiable: Identifiable {
    var id: String { get }
    var timestamp: Date { get }
    var index: Int { get }
}

// Extend existing VideoPlayerModel to conform to VideoIdentifiable
extension VideoPlayerModel: VideoIdentifiable {}

struct RemovableVideoFeed<T: VideoIdentifiable>: View {
    // Environment
    @Environment(\.dismiss) private var dismiss
    
    // Configuration
    let initialIndex: Int
    let handleRemovalLocally: Bool  // If true, handle removal and scrolling locally first
    
    // State
    @Binding var videos: [T]
    @Binding var currentIndex: Int
    @Binding var isDotExpanded: Bool
    
    // Callbacks and view builders
    let onRemove: (T) -> Void
    let buildVideoCell: (T, Bool, @escaping () -> Void) -> AnyView
    let buildControlDot: () -> AnyView
    
    var currentVideo: T? {
        videos.first { $0.index == currentIndex }
    }
    
    private func handleRemove(_ video: T) {
        if handleRemovalLocally {
            // First find where we should scroll to
            let nextIndex: Int?
            if video.index == videos.count - 1 {
                // If removing last video, scroll up
                nextIndex = video.index > 0 ? video.index - 1 : nil
            } else {
                // Otherwise stay at same position to show next video
                nextIndex = video.index
            }
            
            // Update local state first
            withAnimation {
                // Remove the video
                videos.removeAll { $0.id == video.id }
                
                // Reindex remaining videos by updating their indices
                for i in 0..<videos.count {
                    if let videoToUpdate = videos[i] as? VideoPlayerModel {
                        videos[i] = VideoPlayerModel(
                            id: videoToUpdate.id,
                            timestamp: videoToUpdate.timestamp,
                            index: i
                        ) as! T
                    }
                }
                
                // Update scroll position
                if let next = nextIndex {
                    currentIndex = next
                }
            }
            
            // Then notify parent
            onRemove(video)
        } else {
            // Let parent handle removal via onChange
            onRemove(video)
        }
    }
    
    var body: some View {
        Group {
            if videos.isEmpty {
                Color.clear.onAppear { dismiss() }
            } else {
                videoPlayerView
            }
        }
    }
    
    private var videoPlayerView: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(videos) { video in
                        ZStack {
                            buildVideoCell(video, video.index == currentIndex, {
                                handleRemove(video)
                            })
                            
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
                        .id(video.index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .ignoresSafeArea()
            .scrollPosition(id: .init(
                get: { currentIndex },
                set: { newIndex in
                    if let index = newIndex {
                        currentIndex = index
                        if isDotExpanded {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isDotExpanded = false
                            }
                        }
                    }
                }
            ))
            
            buildControlDot()
                .padding(.bottom, 20)
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
}