import SwiftUI

struct VideoThumbnailView: View {
    let videoId: String
    @State private var thumbnail: UIImage?
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.width / 3 * 1.4)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.width / 3 * 1.4)
            }
        }
        .background(Color.black)
        .task {
            if let cached = ThumbnailCache.shared.getCachedUIImageThumbnail(for: videoId) {
                self.thumbnail = cached
            } else {
                // Generate thumbnail using ThumbnailGenerator
                self.thumbnail = await ThumbnailGenerator.getThumbnailUIImage(for: videoId)
            }
        }
    }
} 