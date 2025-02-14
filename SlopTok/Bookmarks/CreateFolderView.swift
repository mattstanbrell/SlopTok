import SwiftUI

struct CreateFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var bookmarksService: BookmarksService
    @State private var folderName = ""
    @State private var selectedVideos: Set<String> = []
    @State private var isCreating = false

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Folder name input
                TextField("Enter folder name", text: $folderName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 22))
                    .frame(height: 50)
                    .padding(.horizontal)
                
                // Video grid
                ScrollView {
                    if bookmarksService.bookmarkedVideos.isEmpty {
                        VStack(spacing: 12) {
                            Text("No bookmarks yet")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text("Bookmarked items will appear here")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 1),
                            GridItem(.flexible(), spacing: 1),
                            GridItem(.flexible(), spacing: 1)
                        ], spacing: 1) {
                            ForEach(bookmarksService.bookmarkedVideos) { video in
                                VideoThumbnailView(videoId: video.id)
                                    .aspectRatio(9/16, contentMode: .fill)
                                    .overlay(
                                        ZStack {
                                            Color.black.opacity(selectedVideos.contains(video.id) ? 0.5 : 0.0)
                                            if selectedVideos.contains(video.id) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.white)
                                                    .font(.title)
                                            }
                                        }
                                    )
                                    .onTapGesture {
                                        if selectedVideos.contains(video.id) {
                                            selectedVideos.remove(video.id)
                                        } else {
                                            selectedVideos.insert(video.id)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            .padding(.top, 20)
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.red.opacity(0.6))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createFolder()
                    }
                    .disabled(folderName.isEmpty || isCreating)
                }
            }
            .background(.ultraThinMaterial)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
    
    private func createFolder() {
        isCreating = true
        Task {
            do {
                try await bookmarksService.createFolder(
                    name: folderName,
                    videoIds: Array(selectedVideos)
                )
                dismiss()
            } catch {
                print("Error creating folder: \(error)")
            }
            isCreating = false
        }
    }
}