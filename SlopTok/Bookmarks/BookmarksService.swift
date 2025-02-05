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
            
            self.bookmarkedVideos = snapshot.documents.compactMap { doc -> BookmarkedVideo? in
                guard let timestamp = doc.data()["timestamp"] as? Timestamp else {
                    return nil
                }
                let folderId = doc.data()["folderId"] as? String
                return BookmarkedVideo(id: doc.documentID, timestamp: timestamp.dateValue(), folderId: folderId)
            }
            self.initialLoadCompleted = true
            
            // Set up real-time listener
            db.collection("users")
                .document(userId)
                .collection("bookmarks")
                .order(by: "timestamp", descending: true)
                .addSnapshotListener { [weak self] querySnapshot, error in
                    guard let self = self,
                          self.initialLoadCompleted,
                          let documents = querySnapshot?.documents else { return }
                    
                    self.bookmarkedVideos = documents.compactMap { doc -> BookmarkedVideo? in
                        guard let timestamp = doc.data()["timestamp"] as? Timestamp else {
                            return nil
                        }
                        let folderId = doc.data()["folderId"] as? String
                        return BookmarkedVideo(id: doc.documentID, timestamp: timestamp.dateValue(), folderId: folderId)
                    }
                }
        } catch {
            print("Error loading bookmarks: \(error.localizedDescription)")
        }
    }
    
    func toggleBookmark(videoId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let bookmarkRef = db.collection("users")
            .document(userId)
            .collection("bookmarks")
            .document(videoId)
        
        if isBookmarked(videoId: videoId) {
            // Remove bookmark
            bookmarkRef.delete()
        } else {
            // Add bookmark
            bookmarkRef.setData([
                "timestamp": FieldValue.serverTimestamp(),
                "folderId": nil  // Will be set when folders are implemented
            ])
        }
    }
    
    func isBookmarked(videoId: String) -> Bool {
        return bookmarkedVideos.contains(where: { $0.id == videoId })
    }
}
