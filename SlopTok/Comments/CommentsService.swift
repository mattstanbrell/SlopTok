import Foundation
import FirebaseFirestore
import FirebaseAuth

struct CommentThread: Identifiable {
    let id: String
    let comment: Comment
    var replies: [CommentThread]
}

class CommentsService: ObservableObject {
    static let shared = CommentsService()
    
    private let db = Firestore.firestore()
    @Published private(set) var commentThreads: [CommentThread] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    private var activeListener: ListenerRegistration?
    private var currentVideoId: String?
    private var pendingLikeTransactions: [String: Int] = [:] // commentId: transactionCount
    
    // Make init private for singleton
    private init() {}
    
    private func organizeIntoThreads(_ comments: [Comment]) -> [CommentThread] {
        // First, create a dictionary of comments by their IDs
        var commentsByParentId: [String?: [Comment]] = [:]
        
        // Group comments by their parent ID
        for comment in comments {
            commentsByParentId[comment.parentCommentId, default: []].append(comment)
        }
        
        // Recursive function to build threads
        func buildThreads(parentId: String?) -> [CommentThread] {
            let children = commentsByParentId[parentId] ?? []
            return children.map { comment in
                CommentThread(
                    id: comment.id,
                    comment: comment,
                    replies: buildThreads(parentId: comment.id)
                )
            }.sorted { $0.comment.timestamp > $1.comment.timestamp }
        }
        
        // Build threads starting from top-level comments (parentId == nil)
        return buildThreads(parentId: nil)
    }
    
    func preloadComments(for videoId: String) {
        // If already loaded for this video, do nothing
        if videoId == currentVideoId { return }
        
        // Clean up previous listener if any
        cleanupCurrentVideo()
        
        // Set new video and start loading
        currentVideoId = videoId
        fetchComments(for: videoId)
    }
    
    private func cleanupCurrentVideo() {
        activeListener?.remove()
        activeListener = nil
        currentVideoId = nil
        commentThreads = []
    }
    
    func fetchComments(for videoId: String) {
        guard let currentUser = Auth.auth().currentUser else { return }
        isLoading = true
        
        activeListener = db.collection("videos").document(videoId).collection("comments")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.error = error
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.commentThreads = []
                    return
                }
                
                // First, create all comments without like status
                let commentsWithoutLikes = documents.compactMap { document -> Comment? in
                    // Skip updates for comments with pending transactions
                    if self.pendingLikeTransactions[document.documentID] != nil {
                        // Find and use the existing comment from our local state
                        if let existingComment = self.findCommentInThreads(commentId: document.documentID) {
                            return existingComment
                        }
                    }
                    return try? document.data(as: Comment.self)
                }
                
                // Then check likes for each comment
                Task {
                    var updatedComments: [Comment] = []
                    
                    for var comment in commentsWithoutLikes {
                        // Skip like status check for comments with pending transactions
                        if self.pendingLikeTransactions[comment.id] != nil {
                            updatedComments.append(comment)
                            continue
                        }
                        
                        let likeDoc = try? await self.db.collection("comments")
                            .document(comment.id)
                            .collection("likes")
                            .document(currentUser.uid)
                            .getDocument()
                        
                        comment.isLikedByCurrentUser = likeDoc?.exists ?? false
                        updatedComments.append(comment)
                    }
                    
                    // Update on main thread
                    await MainActor.run {
                        self.commentThreads = self.organizeIntoThreads(updatedComments)
                    }
                }
            }
    }
    
    // Helper function to find a comment in the current threads
    private func findCommentInThreads(commentId: String) -> Comment? {
        func findInThread(_ thread: CommentThread) -> Comment? {
            if thread.id == commentId {
                return thread.comment
            }
            return thread.replies.compactMap(findInThread).first
        }
        return commentThreads.compactMap(findInThread).first
    }
    
    func addComment(text: String, videoId: String, parentCommentId: String? = nil) {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        let comment = Comment(
            text: text,
            authorId: currentUser.uid,
            authorType: "user",
            authorName: currentUser.displayName ?? "Anonymous",
            authorAvatar: currentUser.photoURL?.absoluteString ?? "",
            parentCommentId: parentCommentId
        )
        
        do {
            try db.collection("videos").document(videoId)
                .collection("comments").document(comment.id)
                .setData(from: comment)
        } catch {
            self.error = error
        }
    }
    
    // Update like status in local state
    private func updateLikeInLocalState(commentId: String, isLiked: Bool) {
        func updateInThreads(_ threads: [CommentThread]) -> [CommentThread] {
            return threads.map { thread in
                if thread.id == commentId {
                    var updatedComment = thread.comment
                    updatedComment.isLikedByCurrentUser = isLiked
                    updatedComment.likeCount += isLiked ? 1 : -1
                    return CommentThread(
                        id: thread.id,
                        comment: updatedComment,
                        replies: thread.replies
                    )
                } else {
                    return CommentThread(
                        id: thread.id,
                        comment: thread.comment,
                        replies: updateInThreads(thread.replies)
                    )
                }
            }
        }
        
        self.commentThreads = updateInThreads(self.commentThreads)
    }
    
    func toggleLike(commentId: String, videoId: String) {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        let likeRef = db.collection("comments").document(commentId)
            .collection("likes").document(currentUser.uid)
        let commentRef = db.collection("videos").document(videoId)
            .collection("comments").document(commentId)
        
        // Find current like status
        let currentLikeStatus = commentThreads.flatMap { thread in
            func findComment(_ thread: CommentThread) -> Comment? {
                if thread.id == commentId {
                    return thread.comment
                }
                return thread.replies.compactMap(findComment).first
            }
            return findComment(thread)
        }.first?.isLikedByCurrentUser ?? false
        
        // Track this transaction
        pendingLikeTransactions[commentId] = (pendingLikeTransactions[commentId] ?? 0) + 1
        let currentTransactionCount = pendingLikeTransactions[commentId] ?? 1
        
        // Optimistically update the UI
        updateLikeInLocalState(commentId: commentId, isLiked: !currentLikeStatus)
        
        db.runTransaction({ (transaction, errorPointer) -> Any? in
            let commentDoc: DocumentSnapshot
            let likeDoc: DocumentSnapshot
            do {
                try commentDoc = transaction.getDocument(commentRef)
                try likeDoc = transaction.getDocument(likeRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            // Get current like count
            guard var comment = try? commentDoc.data(as: Comment.self) else {
                return nil
            }
            
            if likeDoc.exists {
                // Unlike: Remove like document and decrease count
                transaction.deleteDocument(likeRef)
                comment.likeCount = max(0, comment.likeCount - 1)
                comment.isLikedByCurrentUser = false
            } else {
                // Like: Add like document and increase count
                transaction.setData([:], forDocument: likeRef)
                comment.likeCount += 1
                comment.isLikedByCurrentUser = true
            }
            
            // Update the comment document with new like count
            try? transaction.setData(from: comment, forDocument: commentRef)
            return !likeDoc.exists
        }) { [weak self] (_, error) in
            guard let self = self else { return }
            
            // Check if this transaction is still relevant
            if (self.pendingLikeTransactions[commentId] ?? 0) != currentTransactionCount {
                // A newer transaction has started, ignore this result
                return
            }
            
            // Clear the transaction counter if this was the last one
            self.pendingLikeTransactions[commentId] = nil
            
            if let error = error {
                self.error = error
                // Revert the optimistic update if the transaction failed
                self.updateLikeInLocalState(commentId: commentId, isLiked: currentLikeStatus)
            }
        }
    }
    
    // Remove a comment from local state
    private func removeCommentFromLocalState(_ commentId: String) {
        func removeFromThreads(_ threads: [CommentThread]) -> [CommentThread] {
            return threads.filter { $0.id != commentId }.map { thread in
                CommentThread(
                    id: thread.id,
                    comment: thread.comment,
                    replies: removeFromThreads(thread.replies)
                )
            }
        }
        
        self.commentThreads = removeFromThreads(self.commentThreads)
    }
    
    // Add a comment back to local state
    private func addCommentBackToLocalState(_ comment: Comment) {
        // Re-fetch comments to ensure proper thread organization
        if let currentVideoId = currentVideoId {
            preloadComments(for: currentVideoId)
        }
    }
    
    func deleteComment(videoId: String, commentId: String) {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        let commentRef = db.collection("videos").document(videoId)
            .collection("comments").document(commentId)
        
        // First get the comment document
        commentRef.getDocument { [weak self] (document, error) in
            guard let self = self,
                  let document = document,
                  let comment = try? document.data(as: Comment.self),
                  comment.authorId == currentUser.uid else {
                return
            }
            
            // Optimistically remove the comment from local state
            self.removeCommentFromLocalState(commentId)
            
            // Then attempt to delete from Firebase
            commentRef.delete { [weak self] error in
                if let error = error {
                    self?.error = error
                    // If deletion failed, add the comment back
                    self?.addCommentBackToLocalState(comment)
                }
            }
        }
    }
}