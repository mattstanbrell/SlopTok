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
        
        VideoLogger.shared.log(.likesLoaded, videoId: "global", message: "Starting initial likes load")
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("likes")
                .order(by: "timestamp", descending: true)
                .getDocuments()
            
            let documents = snapshot.documents
            if documents.isEmpty {
                VideoLogger.shared.log(.likesLoaded, videoId: "global", message: "No likes found")
                return
            }
            
            self.likedVideos = documents.compactMap { doc -> LikedVideo? in
                guard let timestamp = doc.data()["timestamp"] as? Timestamp else {
                    VideoLogger.shared.log(.likesLoaded, videoId: doc.documentID, message: "Failed to parse like document timestamp")
                    return nil
                }
                return LikedVideo(id: doc.documentID, timestamp: timestamp.dateValue())
            }
            
            self.initialLoadCompleted = true
            
            VideoLogger.shared.log(.likesLoaded, videoId: "global", message: "Loaded \(likedVideos.count) likes")
            
            // Set up listener for real-time updates
            db.collection("users")
                .document(userId)
                .collection("likes")
                .order(by: "timestamp", descending: true)
                .addSnapshotListener { [weak self] querySnapshot, error in
                    guard let self = self,
                          let documents = querySnapshot?.documents else {
                        if let error = error {
                            VideoLogger.shared.log(.likesLoaded, videoId: "global", message: "Failed to listen for likes updates", error: error)
                        }
                        return
                    }
                    
                    VideoLogger.shared.log(.likesLoaded, videoId: "global", message: "Received likes update")
                    self.likedVideos = documents.compactMap { doc -> LikedVideo? in
                        guard let timestamp = doc.data()["timestamp"] as? Timestamp else {
                            VideoLogger.shared.log(.likesLoaded, videoId: doc.documentID, message: "Failed to parse like document timestamp")
                            return nil
                        }
                        return LikedVideo(id: doc.documentID, timestamp: timestamp.dateValue())
                    }
                }
        } catch {
            VideoLogger.shared.log(.likesLoaded, videoId: "global", message: "Failed to load likes", error: error)
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
