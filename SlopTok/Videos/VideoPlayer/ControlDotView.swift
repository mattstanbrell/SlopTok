import SwiftUI
import FirebaseAuth

struct ControlDotView: View {
    @Binding var isExpanded: Bool
    @State private var showProfile = false
    @State private var showComments = false
    @State private var isClosing = false  // Track if control pill is in the process of closing
    let userName: String
    let dotColor: Color  // This will be red when liked, white when not
    @ObservedObject var likesService: LikesService
    @ObservedObject var bookmarksService: BookmarksService
    let currentVideoId: String
    let onBookmarkAction: (() -> Void)?  // New optional action for bookmark remover
    let onProfileAction: (() -> Void)?

    init(isExpanded: Binding<Bool>, userName: String, dotColor: Color, likesService: LikesService, bookmarksService: BookmarksService, currentVideoId: String, onBookmarkAction: (() -> Void)? = nil, onProfileAction: (() -> Void)? = nil) {
        // print("🔄 ControlDotView initialized - isExpanded: \(isExpanded.wrappedValue)")
        self._isExpanded = isExpanded
        self.userName = userName
        self.dotColor = dotColor
        self.likesService = likesService
        self.bookmarksService = bookmarksService
        self.currentVideoId = currentVideoId
        self.onBookmarkAction = onBookmarkAction
        self.onProfileAction = onProfileAction
    }

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
                    // print("👤 Profile button tapped - isClosing: \(isClosing)")
                    if !isClosing {
                        if let profileAction = onProfileAction {
                            profileAction()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showProfile = true
                            }
                        }
                    } // else {
                        // print("❌ Profile button ignored - closing state active")
                    // }
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
                .disabled(isClosing)  // Disable when closing
                
                Spacer()
                
                // Comment button
                Button(action: {
                    // print("💬 Comments button tapped - isClosing: \(isClosing)")
                    if !isClosing {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showComments = true
                        }
                    } // else {
                        // print("❌ Comments button ignored - closing state active")
                    // }
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
                .disabled(isClosing)  // Disable when closing
                
                Spacer()
                
                Button(action: {
                    if !isClosing {
                        shareVideo()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isClosing = true
                            isExpanded = false
                        }
                    }
                }) {
                    Image(systemName: "square.and.arrow.up")
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
                .disabled(isClosing)  // Disable when closing
                
                Spacer()
                
                Button(action: {
                    // print("🔖 Bookmark button tapped - isClosing: \(isClosing)")
                    if !isClosing {
                        if let action = onBookmarkAction {
                            action()
                        } else {
                            bookmarksService.toggleBookmark(videoId: currentVideoId)
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            // print("📍 Setting isClosing = true from bookmark button")
                            isClosing = true
                            isExpanded = false
                        }
                    } // else {
                        // print("❌ Bookmark button ignored - closing state active")
                    // }
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
                .disabled(isClosing)  // Disable when closing
            }
        }
        .frame(width: isExpanded ? UIScreen.main.bounds.width - 32 : 20,
               height: isExpanded ? 48 : 20)
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
                        .frame(width: 24, height: 24)
                }
            }
        )
        .padding(.vertical, isExpanded ? 0 : 20)
        .contentShape(Rectangle())
        .frame(width: isExpanded ? UIScreen.main.bounds.width - 32 : 60,
               height: isExpanded ? 48 : 60)
        .onTapGesture {
            // print("🔄 Pill tapped - current state: expanded=\(isExpanded), closing=\(isClosing)")
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if isExpanded {
                    // print("📍 Setting isClosing = true from pill tap")
                    isClosing = true
                }
                isExpanded.toggle()
            }
        }
        .onChange(of: isExpanded) { newValue in
            // print("🔄 isExpanded changed to \(newValue) - current closing state: \(isClosing)")
            if newValue {
                // print("📍 Setting isClosing = false (expanding)")
                isClosing = false
            } else {
                // print("📍 Setting isClosing = true (closing)")
                isClosing = true
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
    
    private func shareVideo() {
        print("🔗 Share - Starting share process for video: \(currentVideoId)")
        Task {
            do {
                print("🔗 Share - Creating share record in Firebase")
                let shareId = try await ShareService.shared.createShare(videoId: currentVideoId)
                print("✅ Share - Share record created with ID: \(shareId)")
                
                let url = ShareService.shared.createShareURL(videoId: currentVideoId, shareId: shareId)
                print("🔗 Share - Generated URL: \(url)")
                
                await MainActor.run {
                    print("🔗 Share - Presenting share sheet")
                    let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    
                    // Find the currently active window scene
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootVC = window.rootViewController {
                        // For iPad
                        if let popoverController = activityVC.popoverPresentationController {
                            popoverController.sourceView = rootVC.view
                            popoverController.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
                            popoverController.permittedArrowDirections = []
                        }
                        rootVC.present(activityVC, animated: true)
                        print("✅ Share - Share sheet presented")
                    } else {
                        print("❌ Share - Could not find root view controller")
                    }
                }
            } catch {
                print("❌ Share - Error sharing video: \(error)")
            }
        }
    }
}