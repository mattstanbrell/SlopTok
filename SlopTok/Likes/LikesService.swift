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
                .whereField("liked", isEqualTo: true)
                .getDocuments()
            
            let documents = snapshot.documents
            self.likedVideos = documents.compactMap { doc -> LikedVideo? in
                // Use current timestamp if last_seen doesn't exist
                let timestamp = (doc.data()["last_seen"] as? Timestamp) ?? Timestamp(date: Date())
                return LikedVideo(id: doc.documentID, timestamp: timestamp.dateValue())
            }
            
            self.initialLoadCompleted = true
            
            // Set up listener for real-time updates
            db.collection("users")
                .document(userId)
                .collection("videoInteractions")
                .whereField("liked", isEqualTo: true)
                .addSnapshotListener { [weak self] querySnapshot, error in
                    guard let self = self,
                          let documents = querySnapshot?.documents else {
                        if let error = error {
                            return
                        }
                        return
                    }
                    
                    self.likedVideos = documents.compactMap { doc -> LikedVideo? in
                        // Use current timestamp if last_seen doesn't exist
                        let timestamp = (doc.data()["last_seen"] as? Timestamp) ?? Timestamp(date: Date())
                        return LikedVideo(id: doc.documentID, timestamp: timestamp.dateValue())
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
            // Unlike - only update liked status
            interactionRef.setData(["liked": false], merge: true)
        } else {
            // Like - only update liked status
            interactionRef.setData(["liked": true], merge: true)
        }
    }
    
    func isLiked(videoId: String) -> Bool {
        return likedVideos.contains(where: { $0.id == videoId })
    }
}
