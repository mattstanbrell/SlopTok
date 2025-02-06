import FirebaseFirestore
import FirebaseAuth

@MainActor
class LikesService: ObservableObject {
    private let db = Firestore.firestore()
    @Published var likedVideos: [LikedVideo] = []
    private var initialLoadCompleted = false
    
    init() {
        Task {
            await loadLikedVideos()
        }
    }
    
    func loadLikedVideos() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("likes")
                .order(by: "timestamp", descending: true)
                .getDocuments()
            
            let documents = snapshot.documents
            self.likedVideos = documents.compactMap { doc -> LikedVideo? in
                guard let timestamp = doc.data()["timestamp"] as? Timestamp else {
                    return nil
                }
                return LikedVideo(id: doc.documentID, timestamp: timestamp.dateValue())
            }
            
            self.initialLoadCompleted = true
            
            // Set up listener for real-time updates
            db.collection("users")
                .document(userId)
                .collection("likes")
                .order(by: "timestamp", descending: true)
                .addSnapshotListener { [weak self] querySnapshot, error in
                    guard let self = self,
                          let documents = querySnapshot?.documents else {
                        if let error = error {
                            return
                        }
                        return
                    }
                    
                    self.likedVideos = documents.compactMap { doc -> LikedVideo? in
                        guard let timestamp = doc.data()["timestamp"] as? Timestamp else {
                            return nil
                        }
                        return LikedVideo(id: doc.documentID, timestamp: timestamp.dateValue())
                    }
                }
        } catch {
            return
        }
    }
    
    func toggleLike(videoId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let likeRef = db.collection("users")
            .document(userId)
            .collection("likes")
            .document(videoId)
        
        if isLiked(videoId: videoId) {
            // Unlike
            likeRef.delete()
        } else {
            // Like
            likeRef.setData(["timestamp": FieldValue.serverTimestamp()])
        }
    }
    
    func isLiked(videoId: String) -> Bool {
        return likedVideos.contains(where: { $0.id == videoId })
    }
}
