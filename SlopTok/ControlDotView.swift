import SwiftUI
import FirebaseAuth

struct ControlDotView: View {
    @Binding var isExpanded: Bool
    @State private var showProfile = false
    @State private var showComments = false
    let userName: String
    let dotColor: Color  // This will be red when liked, white when not
    @ObservedObject var likesService: LikesService
    @ObservedObject var bookmarksService: BookmarksService
    let currentVideoId: String
    let onBookmarkAction: (() -> Void)?  // New optional action for bookmark remover
    let onProfileAction: (() -> Void)?
    
    private var backgroundColor: Color {
        dotColor.opacity(isExpanded ? 0.3 : 0.2)
    }
    
    private var showRing: Bool {
        !isExpanded && bookmarksService.isBookmarked(videoId: currentVideoId)
    }
    
    var body: some View {
        HStack {
            if isExpanded {
                Button(action: {
                    if let profileAction = onProfileAction {
                        profileAction()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showProfile = true
                        }
                    }
                }) {
                    Image(systemName: "person")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                Circle()
                                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1)
                            .shadow(color: .white.opacity(0.2), radius: 3, x: 0, y: 0)
                        )
                        .padding(.leading, 8)
                        .padding(.vertical, 4)
                }
                
                Spacer()
                
                // Comment button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showComments = true
                    }
                }) {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                Circle()
                                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1)
                            .shadow(color: .white.opacity(0.2), radius: 3, x: 0, y: 0)
                        )
                        .padding(.vertical, 4)
                }
                
                Spacer()
                
                Button(action: {
                    if let action = onBookmarkAction {
                        action()
                    } else {
                        bookmarksService.toggleBookmark(videoId: currentVideoId)
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded = false
                    }
                }) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(bookmarksService.isBookmarked(videoId: currentVideoId) ? .yellow : .white)
                        .frame(width: 36, height: 36)
                        .background(
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                Circle()
                                    .stroke(.white.opacity(0.15), lineWidth: 0.5)
                            }
                            .shadow(color: .black.opacity(0.12), radius: 1.5, x: 0, y: 1)
                            .shadow(color: .white.opacity(0.2), radius: 3, x: 0, y: 0)
                        )
                        .padding(.trailing, 8)
                        .padding(.vertical, 4)
                }
            }
        }
        .frame(width: isExpanded ? UIScreen.main.bounds.width - 32 : 16,
               height: isExpanded ? 48 : 16)
        .background(
            Group {
                if isExpanded {
                    ZStack {
                        dotColor.opacity(0.4)
                    }
                    .background(.regularMaterial)
                    .blur(radius: 20)
                } else {
                    ZStack {
                        dotColor.opacity(0.4)
                    }
                    .background(.regularMaterial)
                    .blur(radius: 5)
                }
            }
        )
        .clipShape(Capsule())
        .overlay(
            Group {
                if showRing {
                    Capsule()
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                        .frame(width: 20, height: 20)
                }
            }
        )
        .padding(20)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(userName: userName, likesService: likesService)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showComments) {
            CommentsSheetView(videoId: currentVideoId)
                .presentationDragIndicator(.visible)
        }
    }
}
