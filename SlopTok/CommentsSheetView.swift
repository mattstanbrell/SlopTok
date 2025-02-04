import SwiftUI
import FirebaseAuth

struct CommentsSheetView: View {
    let videoId: String
    @StateObject private var commentsService = CommentsService()
    @State private var newCommentText = ""
    @State private var replyingTo: Comment?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                if commentsService.isLoading {
                    ProgressView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(commentsService.comments) { comment in
                                CommentView(
                                    comment: comment,
                                    onLike: { commentsService.toggleLike(commentId: comment.id, videoId: videoId) },
                                    onReply: { replyingTo = comment },
                                    onDelete: {
                                        commentsService.deleteComment(videoId: videoId, commentId: comment.id)
                                    }
                                )
                                .padding(.horizontal)
                                Divider()
                            }
                        }
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
                            
                            TextField("Add a comment...", text: $newCommentText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            commentsService.fetchComments(for: videoId)
        }
        .alert("Reply to \(replyingTo?.authorName ?? "")", isPresented: Binding(
            get: { replyingTo != nil },
            set: { if !$0 { replyingTo = nil } }
        )) {
            TextField("Your reply", text: $newCommentText)
            Button("Cancel", role: .cancel) {
                replyingTo = nil
                newCommentText = ""
            }
            Button("Reply") {
                submitComment()
            }
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