import SwiftUI
import FirebaseAuth

struct CommentView: View {
    let comment: Comment
    let onLike: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void
    let indentationLevel: Int
    
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
                    
                    Button(action: onReply) {
                        Text("Reply")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 4)
            }
            
            Spacer(minLength: 16)
            
            // Like button and count
            VStack(alignment: .center, spacing: 4) {
                Button(action: onLike) {
                    Image(systemName: comment.isLikedByCurrentUser ? "heart.fill" : "heart")
                        .font(.system(size: 12))
                        .foregroundColor(comment.isLikedByCurrentUser ? .red : .gray)
                }
                
                if comment.likeCount > 0 {
                    Text(formattedLikeCount)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                } else {
                    Color.clear
                        .frame(height: 15) // Maintain consistent height even when no likes
                }
            }
            .frame(width: 24)
        }
        .padding(.vertical, 8)
        .padding(.leading, indentationLevel > 0 ? 48 : 0)
    }
}

// Helper extension for timestamp formatting
extension Date {
    func timeAgo() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
} 
