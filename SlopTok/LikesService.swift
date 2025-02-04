import FirebaseFirestore
import FirebaseAuth

@MainActor
class LikesService: ObservableObject {
    private let db = Firestore.firestore()
    @Published var likedVideos: Set<String> = []
    private var initialLoadCompleted = false
    
    init() {
        Task {
            await loadLikedVideos()
        }
    }
    
    func loadLikedVideos() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // First, get the initial data
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("likes")
                .getDocuments()
            
            self.likedVideos = Set(snapshot.documents.map { $0.documentID })
            self.initialLoadCompleted = true
            
            // Then set up the real-time listener
            db.collection("users")
                .document(userId)
                .collection("likes")
                .addSnapshotListener { [weak self] querySnapshot, error in
                    guard let self = self,
                          self.initialLoadCompleted,
                          let documents = querySnapshot?.documents else { return }
                    
                    self.likedVideos = Set(documents.map { $0.documentID })
                }
        } catch {
            print("Error loading likes: \(error.localizedDescription)")
        }
    }
    
    func toggleLike(videoId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let likeRef = db.collection("users")
            .document(userId)
            .collection("likes")
            .document(videoId)
        
        if likedVideos.contains(videoId) {
            // Unlike
            likeRef.delete()
        } else {
            // Like
            likeRef.setData(["timestamp": FieldValue.serverTimestamp()])
        }
    }
    
    func isLiked(videoId: String) -> Bool {
        return likedVideos.contains(videoId)
    }
}
