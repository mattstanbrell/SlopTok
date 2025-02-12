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
                .collection("videoInteractions")
                .whereField("liked_timestamp", isGreaterThan: Timestamp(date: Date(timeIntervalSince1970: 0)))
                .getDocuments()
            
            let documents = snapshot.documents
            self.likedVideos = documents.compactMap { doc -> LikedVideo? in
                guard let likedTimestamp = doc.data()["liked_timestamp"] as? Timestamp else { return nil }
                return LikedVideo(id: doc.documentID, timestamp: likedTimestamp.dateValue())
            }
            
            self.initialLoadCompleted = true
            
            // Set up listener for real-time updates
            db.collection("users")
                .document(userId)
                .collection("videoInteractions")
                .whereField("liked_timestamp", isGreaterThan: Timestamp(date: Date(timeIntervalSince1970: 0)))
                .addSnapshotListener { [weak self] querySnapshot, error in
                    guard let self = self,
                          let documents = querySnapshot?.documents else {
                        if let error = error {
                            return
                        }
                        return
                    }
                    
                    self.likedVideos = documents.compactMap { doc -> LikedVideo? in
                        guard let likedTimestamp = doc.data()["liked_timestamp"] as? Timestamp else { return nil }
                        return LikedVideo(id: doc.documentID, timestamp: likedTimestamp.dateValue())
                    }
                }
        } catch {
            return
        }
    }
    
    func toggleLike(videoId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let interactionRef = db.collection("users")
            .document(userId)
            .collection("videoInteractions")
            .document(videoId)
        
        if isLiked(videoId: videoId) {
            // Unlike - remove liked status and timestamp
            interactionRef.updateData([
                "liked": false,
                "liked_timestamp": FieldValue.delete()
            ])
        } else {
            // Like - set liked status and timestamp
            interactionRef.setData([
                "liked": true,
                "liked_timestamp": FieldValue.serverTimestamp()
            ], merge: true)
        }
    }
    
    func isLiked(videoId: String) -> Bool {
        return likedVideos.contains(where: { $0.id == videoId })
    }
}
