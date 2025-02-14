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
                TextField("Folder Name", text: $folderName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                // Video grid
                ScrollView {
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
            .navigationTitle("New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createFolder()
                    }
                    .disabled(folderName.isEmpty || selectedVideos.isEmpty || isCreating)
                }
            }
        }
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

// struct VideoThumbnailView: View {
//     let videoId: String
//     @State private var thumbnail: UIImage?
    
//     var body: some View {
//         Group {
//             if let thumbnail = thumbnail {
//                 Image(uiImage: thumbnail)
//                     .resizable()
//                     .aspectRatio(contentMode: .fill)
//                     .frame(maxWidth: .infinity)
//                     .frame(height: UIScreen.main.bounds.width / 3 * 1.4)
//                     .clipped()
//             } else {
//                 Rectangle()
//                     .fill(Color.gray.opacity(0.3))
//                     .frame(maxWidth: .infinity)
//                     .frame(height: UIScreen.main.bounds.width / 3 * 1.4)
//             }
//         }
//         .background(Color.black)
//         .task {
//             if let cached = ThumbnailCache.shared.getCachedUIImageThumbnail(for: videoId) {
//                 self.thumbnail = cached
//             } else {
//                 // Generate thumbnail using ThumbnailGenerator
//                 self.thumbnail = await ThumbnailGenerator.getThumbnailUIImage(for: videoId)
//             }
//         }
//     }
// } 