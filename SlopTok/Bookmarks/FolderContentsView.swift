import SwiftUI

struct FolderContentsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bookmarksService: BookmarksService
    let folder: BookmarkFolder
    
    private var folderVideos: [BookmarkedVideo] {
        bookmarksService.bookmarkedVideos.filter { $0.folderIds.contains(folder.id) }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 1),
                    GridItem(.flexible(), spacing: 1),
                    GridItem(.flexible(), spacing: 1)
                ], spacing: 1) {
                    ForEach(folderVideos) { video in
                        VideoThumbnailView(videoId: video.id)
                            .aspectRatio(9/16, contentMode: .fill)
                            .contextMenu {
                                Button(role: .destructive) {
                                    removeFromFolder(videoId: video.id)
                                } label: {
                                    Label("Remove from Folder", systemImage: "folder.badge.minus")
                                }
                            }
                    }
                }
            }
            .navigationTitle(folder.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            deleteFolder()
                        } label: {
                            Label("Delete Folder", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
    }
    
    private func removeFromFolder(videoId: String) {
        Task {
            do {
                try await bookmarksService.removeVideoFromFolder(videoId: videoId, folderId: folder.id)
            } catch {
                print("Error removing video from folder: \(error)")
            }
        }
    }
    
    private func deleteFolder() {
        Task {
            do {
                try await bookmarksService.deleteFolder(folderId: folder.id)
                dismiss()
            } catch {
                print("Error deleting folder: \(error)")
            }
        }
    }
} 