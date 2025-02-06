import SwiftUI

struct CachedAvatarView: View {
    let size: CGFloat
    @State private var image: UIImage?
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle()
                    .foregroundColor(.gray.opacity(0.3))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task {
            // Load image asynchronously
            image = await AvatarCache.shared.getAvatar()
        }
    }
}
