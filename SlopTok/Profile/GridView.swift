import SwiftUI

// Allow String to be used as Identifiable for fullScreenCover
extension String: Identifiable {
    public var id: String { self }
}

struct GridView<T: VideoModel, V: View>: View {
    let videos: [T]
    let fullscreenContent: ([T], String) -> V
    @State private var selectedVideoId: String?
    @State private var showCreateFolder = false
    @State private var selectedFolder: BookmarkFolder?
    let bookmarksService: BookmarksService?
    
    init(
        videos: [T],
        fullscreenContent: @escaping ([T], String) -> V,
        bookmarksService: BookmarksService? = nil
    ) {
        self.videos = videos
        self.fullscreenContent = fullscreenContent
        self.bookmarksService = bookmarksService
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Show folders section if this is a bookmarks grid
                if let bookmarksService = bookmarksService {
                    HStack {
                        Text("Folders")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button {
                            showCreateFolder = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.horizontal)
                    
                    if !bookmarksService.bookmarkFolders.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(bookmarksService.bookmarkFolders) { folder in
                                    VStack {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.gray.opacity(0.2))
                                            
                                            Image(systemName: "folder.fill")
                                                .font(.system(size: 30))
                                                .foregroundColor(.yellow)
                                        }
                                        .frame(width: 60, height: 60)
                                        
                                        Text(folder.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                    }
                                    .frame(width: 80)
                                    .onTapGesture {
                                        selectedFolder = folder
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    if !videos.isEmpty {
                        Text("All Bookmarks")
                            .font(.headline)
                            .padding(.horizontal)
                    }
                }
                
                // Videos grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 1),
                    GridItem(.flexible(), spacing: 1),
                    GridItem(.flexible(), spacing: 1)
                ], spacing: 1) {
                    ForEach(videos) { video in
                        VideoThumbnailView(videoId: video.id)
                            .aspectRatio(9/16, contentMode: .fill)
                            .onTapGesture {
                                selectedVideoId = video.id
                            }
                    }
                }
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .fullScreenCover(item: $selectedVideoId) { videoId in
            fullscreenContent(videos, videoId)
        }
        .sheet(isPresented: $showCreateFolder) {
            if let bookmarksService = bookmarksService {
                CreateFolderView(bookmarksService: bookmarksService)
            }
        }
        .sheet(item: $selectedFolder) { folder in
            if let bookmarksService = bookmarksService {
                FolderContentsView(bookmarksService: bookmarksService, folder: folder)
            }
        }
    }
}