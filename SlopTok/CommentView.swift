import SwiftUI
import FirebaseAuth

struct CommentView: View {
    let comment: Comment
    let onLike: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // Author avatar
                AsyncImage(url: URL(string: comment.authorAvatar)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .foregroundColor(.gray.opacity(0.3))
                }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    // Author name
                    Text(comment.authorName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    // Comment text
                    Text(comment.text)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                // Timestamp
                Text(comment.timestamp.timeAgo())
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            HStack(spacing: 16) {
                // Like button
                Button(action: onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: comment.isLikedByCurrentUser ? "heart.fill" : "heart")
                        Text("\(comment.likeCount)")
                            .font(.caption)
                    }
                }
                .foregroundColor(comment.isLikedByCurrentUser ? .red : .gray)
                
                // Reply button
                Button(action: onReply) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.left")
                        Text("Reply")
                            .font(.caption)
                    }
                }
                .foregroundColor(.gray)
                
                // Delete button (only show for user's own comments)
                if comment.authorType == "user" && comment.authorId == Auth.auth().currentUser?.uid {
                    Button(action: { showDeleteAlert = true }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .alert(isPresented: $showDeleteAlert) {
                        Alert(
                            title: Text("Delete Comment"),
                            message: Text("Are you sure you want to delete this comment?"),
                            primaryButton: .destructive(Text("Delete"), action: onDelete),
                            secondaryButton: .cancel()
                        )
                    }
                }
            }
            .padding(.leading, 52) // Align with the text
        }
        .padding(.vertical, 8)
    }
}

// Helper extension for timestamp formatting
extension Date {
    func timeAgo() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: Date())
    }
} 
