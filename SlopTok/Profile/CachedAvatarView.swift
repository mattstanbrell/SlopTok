import SwiftUI

struct CachedAvatarView: View {
    let size: CGFloat
    @State private var image: UIImage?
    
    private var avatarSize: AvatarSize {
        switch size {
        case 90...: return .large   // Profile view (90px)
        case 32...: return .medium  // All comment sheet avatars
        default: return .small      // Fallback
        }
    }
    
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
            image = await AvatarCache.shared.getAvatar(size: avatarSize)
        }
    }
}
