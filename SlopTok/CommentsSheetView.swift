import SwiftUI
import FirebaseAuth

struct CommentsSheetView: View {
    let videoId: String
    @StateObject private var commentsService = CommentsService()
    @State private var newCommentText = ""
    @State private var replyingTo: Comment?
    @Environment(\.dismiss) private var dismiss
    
    @ViewBuilder
    private func commentThreadView(_ thread: CommentThread, indentationLevel: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CommentView(
                comment: thread.comment,
                onLike: { commentsService.toggleLike(commentId: thread.comment.id, videoId: videoId) },
                onReply: { replyingTo = thread.comment },
                onDelete: {
                    commentsService.deleteComment(videoId: videoId, commentId: thread.comment.id)
                },
                indentationLevel: indentationLevel
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if !thread.replies.isEmpty {
                ForEach(thread.replies) { reply in
                    commentThreadView(reply, indentationLevel: 1)
                }
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if commentsService.isLoading {
                    ProgressView()
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(commentsService.commentThreads) { thread in
                                commentThreadView(thread)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if thread.id != commentsService.commentThreads.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    
                    // Comment input area
                    VStack(spacing: 0) {
                        Divider()
                        HStack(spacing: 12) {
                            if let user = Auth.auth().currentUser {
                                AsyncImage(url: URL(string: user.photoURL?.absoluteString ?? "")) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Circle()
                                        .foregroundColor(.gray.opacity(0.3))
                                }
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                            }
                            
                            TextField(replyingTo == nil ? "Add a comment..." : "Reply to \(replyingTo?.authorName ?? "")...",
                                    text: $newCommentText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
                            if replyingTo != nil {
                                Button(action: { replyingTo = nil }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            Button(action: submitComment) {
                                Text("Post")
                                    .fontWeight(.semibold)
                            }
                            .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                    }
                }
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.height(UIScreen.main.bounds.height * 0.7)])
        .presentationDragIndicator(.visible)
        .onAppear {
            commentsService.fetchComments(for: videoId)
        }
    }
    
    private func submitComment() {
        guard !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        commentsService.addComment(
            text: newCommentText,
            videoId: videoId,
            parentCommentId: replyingTo?.id
        )
        
        newCommentText = ""
        replyingTo = nil
    }
} 
