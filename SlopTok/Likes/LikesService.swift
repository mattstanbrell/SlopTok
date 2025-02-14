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
                .order(by: "liked_timestamp", descending: true)
                .getDocuments()
            
            let documents = snapshot.documents
            self.likedVideos = documents.compactMap { doc -> LikedVideo? in
                guard let likedTimestamp = doc.data()["liked_timestamp"] as? Timestamp else { return nil }
                let prompt = doc.data()["prompt"] as? String
                return LikedVideo(id: doc.documentID, timestamp: likedTimestamp.dateValue(), prompt: prompt)
            }
            
            self.initialLoadCompleted = true
            
            // Set up listener for real-time updates
            db.collection("users")
                .document(userId)
                .collection("videoInteractions")
                .whereField("liked_timestamp", isGreaterThan: Timestamp(date: Date(timeIntervalSince1970: 0)))
                .order(by: "liked_timestamp", descending: true)
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
                        let prompt = doc.data()["prompt"] as? String
                        return LikedVideo(id: doc.documentID, timestamp: likedTimestamp.dateValue(), prompt: prompt)
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
            // Unlike - remove timestamp
            interactionRef.updateData([
                "liked_timestamp": FieldValue.delete()
            ])
        } else {
            // Like - set timestamp
            interactionRef.setData([
                "liked_timestamp": FieldValue.serverTimestamp()
            ], merge: true)
        }
    }
    
    func isLiked(videoId: String) -> Bool {
        return likedVideos.contains(where: { $0.id == videoId })
    }
}
