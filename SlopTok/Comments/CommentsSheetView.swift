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
                        .padding(.vertical, 4)
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
                    HStack(spacing: 10) {
                        if let user = Auth.auth().currentUser {
                            CachedAvatarView(size: 32)
                        }
                        
                        HStack {
                            TextField(replyingTo == nil ? "Add a comment..." : "Reply to \(replyingTo?.authorName ?? "")...",
                                    text: $newCommentText)
                                .focused($isInputActive)
                            
                            if replyingTo != nil {
                                Button(action: { replyingTo = nil }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                            
                            // Invisible placeholder to maintain consistent height
                            if newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Image(systemName: "paperplane.fill")
                                    .foregroundColor(.clear)
                                    .frame(width: 28, height: 28)
                            } else {
                                Button(action: submitComment) {
                                    Image(systemName: "paperplane.fill")
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .semibold))
                                        .frame(width: 28, height: 28)
                                        .background(Color.blue)
                                        .clipShape(Circle())
                                }
                                .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                            }
                        }
                        .padding(8)
                        .background(Color(uiColor: UIColor { traitCollection in
                            traitCollection.userInterfaceStyle == .dark ? 
                                UIColor(white: 0.2, alpha: 1.0) :
                                UIColor.systemGray6
                        }))
                        .cornerRadius(16)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    .background(.thinMaterial)
                }
            }
        }
        .background(Color(.systemBackground).opacity(0.5))
        .presentationDetents([.height(UIScreen.main.bounds.height * 0.7)])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
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
