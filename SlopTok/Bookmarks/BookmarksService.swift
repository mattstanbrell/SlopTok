import FirebaseFirestore
import FirebaseAuth

@MainActor
class BookmarksService: ObservableObject {
    private let db = Firestore.firestore()
    @Published var bookmarkedVideos: [BookmarkedVideo] = []
    private var initialLoadCompleted = false
    
    init() {
        Task {
            await loadBookmarkedVideos()
        }
    }
    
    func loadBookmarkedVideos() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("bookmarks")
                .order(by: "timestamp", descending: true)
                .getDocuments()
            
            let documents = snapshot.documents
            if documents.isEmpty {
                return
            }
            
            self.bookmarkedVideos = documents.compactMap { doc -> BookmarkedVideo? in
                guard let timestamp = doc.data()["timestamp"] as? Timestamp else {
                    return nil
                }
                return BookmarkedVideo(id: doc.documentID, timestamp: timestamp.dateValue())
            }
            
            self.initialLoadCompleted = true
            
            // Set up listener for real-time updates
            db.collection("users")
                .document(userId)
                .collection("bookmarks")
                .order(by: "timestamp", descending: true)
                .addSnapshotListener { [weak self] querySnapshot, error in
                    guard let self = self,
                          let documents = querySnapshot?.documents else {
                        if let error = error {
                            return
                        }
                        return
                    }
                    
                    self.bookmarkedVideos = documents.compactMap { doc -> BookmarkedVideo? in
                        guard let timestamp = doc.data()["timestamp"] as? Timestamp else {
                            return nil
                        }
                        return BookmarkedVideo(id: doc.documentID, timestamp: timestamp.dateValue())
                    }
                }
        } catch {
            return
        }
    }
    
    func toggleBookmark(videoId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let bookmarkRef = db.collection("users")
            .document(userId)
            .collection("bookmarks")
            .document(videoId)
        
        if isBookmarked(videoId: videoId) {
            // Unbookmark
            bookmarkRef.delete()
        } else {
            // Bookmark
            bookmarkRef.setData(["timestamp": FieldValue.serverTimestamp()])
        }
    }
    
    func isBookmarked(videoId: String) -> Bool {
        return bookmarkedVideos.contains(where: { $0.id == videoId })
    }
}
