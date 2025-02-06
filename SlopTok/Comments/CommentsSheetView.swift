import SwiftUI
import FirebaseAuth
import Combine

struct CommentsSheetView: View {
    let videoId: String
    @ObservedObject private var commentsService = CommentsService.shared
    @State private var newCommentText = ""
    @State private var replyingTo: Comment?
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isInputActive: Bool

    private var totalCommentCount: Int {
        var count = 0
        func countComments(_ threads: [CommentThread]) {
            for thread in threads {
                count += 1
                countComments(thread.replies)
            }
        }
        countComments(commentsService.commentThreads)
        return count
    }
    
    private var formattedCommentCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: totalCommentCount)) ?? "\(totalCommentCount)"
    }
    
    private var flattenedComments: [(Comment, Int)] {
        var comments: [(Comment, Int)] = []
        
        for thread in commentsService.commentThreads {
            comments.append((thread.comment, 0))
            for reply in thread.replies {
                comments.append((reply.comment, 1))
            }
        }
        
        return comments
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Comment count header
            Text("\(formattedCommentCount) comments")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.top, 8)
            
            if commentsService.isLoading {
                ProgressView()
            } else {
                List {
                    ForEach(flattenedComments, id: \.0.id) { comment, indentationLevel in
                        CommentView(
                            comment: comment,
                            onLike: { commentsService.toggleLike(commentId: comment.id, videoId: videoId) },
                            onReply: { 
                                replyingTo = comment
                                isInputActive = true
                            },
                            onDelete: {
                                commentsService.deleteComment(videoId: videoId, commentId: comment.id)
                            },
                            indentationLevel: indentationLevel,
                            isReplyTarget: replyingTo?.id == comment.id
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(replyingTo?.id == comment.id ? Color.pink.opacity(0.1) : Color.clear)
                        .listRowSeparator(.hidden)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isInputActive {
                                if replyingTo?.id == comment.id {
                                    replyingTo = nil
                                } else {
                                    replyingTo = comment
                                }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if comment.authorType == "user" && comment.authorId == Auth.auth().currentUser?.uid {
                                Button(role: .destructive, action: {
                                    commentsService.deleteComment(videoId: videoId, commentId: comment.id)
                                }) {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(commentsService.isLoading)
                
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
                            .focused($isInputActive)
                        
                        if replyingTo != nil {
                            Button(action: { replyingTo = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Button(action: submitComment) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                        }
                        .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                }
            }
        }
        .presentationDetents([.height(UIScreen.main.bounds.height * 0.7)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isInputActive)  // Prevent dismissal when keyboard is active
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
