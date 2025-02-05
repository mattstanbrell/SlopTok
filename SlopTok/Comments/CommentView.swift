import SwiftUI
import FirebaseAuth

struct CommentView: View {
    let comment: Comment
    let onLike: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void
    let indentationLevel: Int
    @State private var currentTime = Date()
    
    private let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    
    private var formattedLikeCount: String {
        if comment.likeCount >= 1000 {
            let count = Double(comment.likeCount) / 1000.0
            return String(format: "%.1fK", count)
        }
        return "\(comment.likeCount)"
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Author avatar
            AsyncImage(url: URL(string: comment.authorAvatar)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .foregroundColor(.gray.opacity(0.3))
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
            
            // Comment content
            VStack(alignment: .leading, spacing: 2) {
                // Author name
                Text(comment.authorName)
                    .font(.system(size: 14, weight: .semibold))
                
                // Comment text
                Text(comment.text)
                    .font(.system(size: 14))
                
                // Timestamp and actions
                HStack(spacing: 16) {
                    Text(comment.timestamp.timeAgo())
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                        .id(currentTime) // Force refresh when currentTime changes
                    
                    Button(action: onReply) {
                        Text("Reply")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Like button and count aligned to bottom
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Button(action: onLike) {
                        Image(systemName: comment.isLikedByCurrentUser ? "heart.fill" : "heart")
                            .font(.system(size: 12))
                            .foregroundColor(comment.isLikedByCurrentUser ? .red : .gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                    Text(formattedLikeCount)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .frame(width: 24, height: 15)
                        .opacity(comment.likeCount > 0 ? 1 : 0)
                }
            }
            .frame(width: 24, alignment: .bottom)
        }
        .padding(.vertical, 8)
        .padding(.leading, indentationLevel > 0 ? 48 : 0)
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
}

// Helper extension for timestamp formatting
extension Date {
    func timeAgo() -> String {
        let seconds = Date().timeIntervalSince(self)
        if seconds < 60 {
            return "just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
} 