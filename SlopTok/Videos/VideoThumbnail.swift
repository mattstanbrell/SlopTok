import SwiftUI

struct VideoThumbnail: View {
    let videoId: String
    let thumbnail: Image?
    
    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                thumbnail
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
    }
}

#if DEBUG
struct VideoThumbnail_Previews: PreviewProvider {
    static var previews: some View {
        VideoThumbnail(videoId: "example", thumbnail: nil)
            .previewLayout(.sizeThatFits)
    }
}
#endif