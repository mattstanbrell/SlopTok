import Foundation
import FirebaseFirestore
import FirebaseAuth

class CommentsService: ObservableObject {
    private let db = Firestore.firestore()
    @Published var comments: [Comment] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    func fetchComments(for videoId: String) {
        guard let currentUser = Auth.auth().currentUser else { return }
        isLoading = true
        
        db.collection("videos").document(videoId).collection("comments")
            .order(by: "timestamp", descending: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self = self else { return }
                self.isLoading = false
                
                if let error = error {
                    self.error = error
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self.comments = []
                    return
                }
                
                // First, create all comments without like status
                let commentsWithoutLikes = documents.compactMap { document -> Comment? in
                    try? document.data(as: Comment.self)
                }
                
                // Then check likes for each comment
                Task {
                    var updatedComments: [Comment] = []
                    
                    for var comment in commentsWithoutLikes {
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
                        self.comments = updatedComments
                    }
                }
            }
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
    
    func toggleLike(commentId: String, videoId: String) {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        let likeRef = db.collection("comments").document(commentId)
            .collection("likes").document(currentUser.uid)
        let commentRef = db.collection("videos").document(videoId)
            .collection("comments").document(commentId)
        
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
            if let error = error {
                self?.error = error
            }
        }
    }
    
    func deleteComment(videoId: String, commentId: String) {
        guard let currentUser = Auth.auth().currentUser else { return }
        
        let commentRef = db.collection("videos").document(videoId)
            .collection("comments").document(commentId)
        
        commentRef.getDocument { [weak self] (document, error) in
            guard let document = document,
                  let comment = try? document.data(as: Comment.self),
                  comment.authorId == currentUser.uid else {
                return
            }
            
            commentRef.delete { error in
                if let error = error {
                    self?.error = error
                }
            }
        }
    }
} 