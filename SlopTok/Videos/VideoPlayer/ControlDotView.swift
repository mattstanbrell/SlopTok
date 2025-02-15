import SwiftUI
import FirebaseAuth

struct ControlDotView: View {
    @Binding var isExpanded: Bool
    @State private var showProfile = false
    @State private var showComments = false
    @State private var isClosing = false
    @State private var showFolderSelection = false
    @State private var showVideoGeneration = false

    let userName: String
    let dotColor: Color
    @ObservedObject var likesService: LikesService
    @ObservedObject var bookmarksService: BookmarksService
    let currentVideoId: String
    let onBookmarkAction: (() -> Void)?
    let onProfileAction: (() -> Void)?

    /// Width of the pill in expanded state
    private var finalWidth: CGFloat {
        min(280, UIScreen.main.bounds.width - 32)
    }
    /// Size of the collapsed dot (a circle)
    private let collapsedSize: CGFloat = 20

    init(
        isExpanded: Binding<Bool>,
        userName: String,
        dotColor: Color,
        likesService: LikesService,
        bookmarksService: BookmarksService,
        currentVideoId: String,
        onBookmarkAction: (() -> Void)? = nil,
        onProfileAction: (() -> Void)? = nil
    ) {
        self._isExpanded = isExpanded
        self.userName = userName
        self.dotColor = dotColor
        self.likesService = likesService
        self.bookmarksService = bookmarksService
        self.currentVideoId = currentVideoId
        self.onBookmarkAction = onBookmarkAction
        self.onProfileAction = onProfileAction
    }

    /// Show a ring if collapsed *and* bookmarked
    private var showRing: Bool {
        !isExpanded && bookmarksService.isBookmarked(videoId: currentVideoId)
    }

    var body: some View {
        // 1) Horizontal container, centered, with a 60-pt height
        HStack(alignment: .center) {
            Spacer()
            pillContent
            Spacer()
        }
        .frame(height: 60)   // Ensures a tall enough hit area, center-aligned
        .sheet(isPresented: $showProfile) {
            ProfileView(userName: userName, likesService: likesService)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showVideoGeneration) {
            VideoGenerationView(
                videoId: currentVideoId,
                likesService: likesService,
                bookmarksService: bookmarksService
            )
        }
        .sheet(isPresented: $showFolderSelection) {
            FolderSelectionView(
                bookmarksService: bookmarksService,
                videoId: currentVideoId
            )
        }
    }

    private var pillContent: some View {
        // 2) Actual dot/capsule content
        HStack(spacing: 0) {
            if isExpanded {
                // -- Profile Button --
                Button {
                    if !isClosing {
                        if let profileAction = onProfileAction {
                            profileAction()
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                showProfile = true
                            }
                        }
                    }
                } label: {
                    buttonIcon("person")
                        .padding(.leading, 8)
                }
                .disabled(isClosing)

                Spacer()

                // -- Video Generation Button --
                Button {
                    if !isClosing {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showVideoGeneration = true
                        }
                    }
                } label: {
                    buttonIcon("video.badge.plus")
                }
                .disabled(isClosing)

                Spacer()

                // -- Share Button --
                Button {
                    if !isClosing {
                        shareVideo()
                    }
                } label: {
                    buttonIcon("square.and.arrow.up")
                }
                .disabled(isClosing)

                Spacer()

                // -- Bookmark Button --
                Button {
                    if !isClosing {
                        if let bookmarkAction = onBookmarkAction {
                            bookmarkAction()
                        } else {
                            bookmarksService.toggleBookmark(videoId: currentVideoId)
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isClosing = true
                            isExpanded = false
                        }
                    }
                } label: {
                    let color: Color =
                        bookmarksService.isBookmarked(videoId: currentVideoId) ? .yellow : .white
                    buttonIcon("bookmark", foregroundColor: color)
                        .padding(.trailing, 8)
                }
                .simultaneousGesture(
                    LongPressGesture()
                        .onEnded { _ in
                            if !isClosing && bookmarksService.bookmarkFolders.count > 0 {
                                showFolderSelection = true
                            }
                        }
                )
                .disabled(isClosing)
            }
        }
        // 3) Animate .frame from 20×20 (circle) to (finalWidth)×48 (capsule)
        .frame(
            width: isExpanded ? finalWidth : collapsedSize,
            height: isExpanded ? 48 : collapsedSize
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
        .background(
            ZStack {
                Color.clear
                    .background(.ultraThinMaterial)
                if likesService.isLiked(videoId: currentVideoId) {
                    Color.red.opacity(0.2)
                }
            }
        )
        .clipShape(Capsule())
        // 4) A ring around the dot if bookmarked+collapsed
        .overlay(
            Group {
                if showRing {
                    Capsule()
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                        .frame(width: 24, height: 24) // Slightly larger => small gap
                }
            }
        )
        // Create a larger tappable area while keeping visual size
        .frame(width: isExpanded ? nil : 60, height: isExpanded ? nil : 60)
        // So the entire area is tappable
        .contentShape(Rectangle())
        .onTapGesture {
            if !isExpanded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if isExpanded {
                        isClosing = true
                    }
                    isExpanded.toggle()
                }
            }
        }
        .onChange(of: isExpanded) { newValue in
            // Keep track of closing vs expanding
            isClosing = !newValue
        }
    }

    // Helper to create a button icon with the same style
    private func buttonIcon(_ name: String, foregroundColor: Color = .white) -> some View {
        Image(systemName: name + ".fill")
            .font(.system(size: 22, weight: .medium))
            .foregroundColor(foregroundColor)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
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

                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootVC = window.rootViewController {
                        if let popoverController = activityVC.popoverPresentationController {
                            popoverController.sourceView = rootVC.view
                            popoverController.sourceRect = CGRect(
                                x: UIScreen.main.bounds.midX,
                                y: UIScreen.main.bounds.midY,
                                width: 0, height: 0
                            )
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

struct FolderSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bookmarksService: BookmarksService
    let videoId: String
    @State private var selectedFolders: Set<String>
    @State private var isUpdating = false
    
    init(bookmarksService: BookmarksService, videoId: String) {
        self.bookmarksService = bookmarksService
        self.videoId = videoId
        
        // Initialize selected folders based on current video's folders
        let currentFolders = bookmarksService.getFolders(for: videoId)
        _selectedFolders = State(initialValue: Set(currentFolders.map { $0.id }))
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(bookmarksService.bookmarkFolders) { folder in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.yellow)
                        
                        Text(folder.name)
                        
                        Spacer()
                        
                        if selectedFolders.contains(folder.id) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedFolders.contains(folder.id) {
                            selectedFolders.remove(folder.id)
                        } else {
                            selectedFolders.insert(folder.id)
                        }
                    }
                }
            }
            .navigationTitle("Select Folders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        updateFolders()
                    }
                    .disabled(isUpdating)
                }
            }
        }
    }
    
    private func updateFolders() {
        isUpdating = true
        Task {
            do {
                try await bookmarksService.addVideoToFolders(
                    videoId: videoId,
                    folderIds: Array(selectedFolders)
                )
                dismiss()
            } catch {
                print("Error updating folders: \(error)")
            }
            isUpdating = false
        }
    }
}
