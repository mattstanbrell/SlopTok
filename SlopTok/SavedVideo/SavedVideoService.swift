import FirebaseFirestore
import FirebaseAuth

@MainActor
class SavedVideoService<T: SavedVideo>: ObservableObject {
    private let db = Firestore.firestore()
    @Published public var videos: [T] = []
    private var initialLoadCompleted = false
    private let collectionName: String
    private let createVideo: (String, Date) -> T
    
    init(collectionName: String, createVideo: @escaping (String, Date) -> T) {
        self.collectionName = collectionName
        self.createVideo = createVideo
        Task {
            await loadVideos()
        }
    }
    
    func loadVideos() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection(collectionName)
                .order(by: "timestamp", descending: true)
                .getDocuments()
            
            let documents = snapshot.documents
            self.videos = documents.compactMap { [self] doc -> T? in
                guard let timestamp = doc.data()["timestamp"] as? Timestamp else {
                    return nil
                }
                return self.createVideo(doc.documentID, timestamp.dateValue())
            }
            
            self.initialLoadCompleted = true
            
            // Set up listener for real-time updates
            db.collection("users")
                .document(userId)
                .collection(collectionName)
                .order(by: "timestamp", descending: true)
                .addSnapshotListener { [weak self] querySnapshot, error in
                    guard let self = self,
                          let documents = querySnapshot?.documents else {
                        if let error = error {
                            return
                        }
                        return
                    }
                    
                    self.videos = documents.compactMap { [self] doc -> T? in
                        guard let timestamp = doc.data()["timestamp"] as? Timestamp else {
                            return nil
                        }
                        return self.createVideo(doc.documentID, timestamp.dateValue())
                    }
                }
        } catch {
            return
        }
    }
    
    func toggleSavedState(videoId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let ref = db.collection("users")
            .document(userId)
            .collection(collectionName)
            .document(videoId)
        
        if isSaved(videoId: videoId) {
            ref.delete()
        } else {
            ref.setData(["timestamp": FieldValue.serverTimestamp()])
        }
    }
    
    func isSaved(videoId: String) -> Bool {
        return videos.contains(where: { $0.id == videoId })
    }
}
