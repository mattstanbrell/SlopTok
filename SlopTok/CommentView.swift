import SwiftUI
import FirebaseAuth

struct CommentView: View {
    let comment: Comment
    let onLike: () -> Void
    let onReply: () -> Void
    let onDelete: () -> Void
    let indentationLevel: Int
    @State private var showDeleteAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        // Author name
                        Text(comment.authorName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        // Timestamp
                        Text("·")
                            .foregroundColor(.gray)
                        Text(comment.timestamp.timeAgo())
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    // Comment text
                    Text(comment.text)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    
                    // Action buttons
                    HStack(spacing: 16) {
                        // Like button
                        Button(action: onLike) {
                            HStack(spacing: 4) {
                                Image(systemName: comment.isLikedByCurrentUser ? "heart.fill" : "heart")
                                    .font(.system(size: 14))
                                if comment.likeCount > 0 {
                                    Text("\(comment.likeCount)")
                                        .font(.caption)
                                }
                            }
                        }
                        .foregroundColor(comment.isLikedByCurrentUser ? .red : .gray)
                        
                        // Reply button
                        Button(action: onReply) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrowshape.turn.up.left")
                                    .font(.system(size: 14))
                                Text("Reply")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(.gray)
                        
                        // Delete button (only show for user's own comments)
                        if comment.authorType == "user" && comment.authorId == Auth.auth().currentUser?.uid {
                            Button(action: { showDeleteAlert = true }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14))
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
                    .padding(.top, 4)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, indentationLevel > 0 ? 32 : 0) // Only indent replies
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
