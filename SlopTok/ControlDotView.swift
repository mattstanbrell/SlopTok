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
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .padding(.leading, 8)
                }
                
                Spacer()
                
                // Comment button
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        showComments = true
                    }
                }) {
                    Image(systemName: "bubble.left.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
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
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 20))
                        .foregroundColor(bookmarksService.isBookmarked(videoId: currentVideoId) ? .yellow : .white)
                        .padding(.trailing, 8)
                }
            }
        }
        .frame(width: isExpanded ? UIScreen.main.bounds.width - 32 : 16,
               height: isExpanded ? 40 : 16)
        .background(backgroundColor)
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