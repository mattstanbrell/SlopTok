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
        print("🔖 [BookmarksService] Loading bookmarked videos for user: \(userId)")
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("bookmarks")
                .order(by: "timestamp", descending: true)
                .getDocuments()
            
            let documents = snapshot.documents
            print("🔖 [BookmarksService] Initial load - Document count: \(documents.count)")
            
            self.bookmarkedVideos = documents.compactMap { doc -> BookmarkedVideo? in
                guard let timestamp = doc.data()["timestamp"] as? Timestamp else {
                    print("🔖 [BookmarksService] Warning: Missing timestamp for document: \(doc.documentID)")
                    return nil
                }
                return BookmarkedVideo(id: doc.documentID, timestamp: timestamp.dateValue())
            }
            
            print("🔖 [BookmarksService] Initial state set - Bookmarked videos count: \(self.bookmarkedVideos.count)")
            self.initialLoadCompleted = true
            
            // Set up listener for real-time updates
            print("🔖 [BookmarksService] Setting up Firestore listener")
            db.collection("users")
                .document(userId)
                .collection("bookmarks")
                .order(by: "timestamp", descending: true)
                .addSnapshotListener { [weak self] querySnapshot, error in
                    guard let self = self else {
                        print("🔖 [BookmarksService] Warning: Self is nil in listener")
                        return
                    }
                    
                    if let error = error {
                        print("🔖 [BookmarksService] Error in listener: \(error)")
                        return
                    }
                    
                    guard let documents = querySnapshot?.documents else {
                        print("🔖 [BookmarksService] Warning: No documents in snapshot")
                        return
                    }
                    
                    print("🔖 [BookmarksService] Listener update - Document count: \(documents.count)")
                    let oldCount = self.bookmarkedVideos.count
                    
                    self.bookmarkedVideos = documents.compactMap { doc -> BookmarkedVideo? in
                        guard let timestamp = doc.data()["timestamp"] as? Timestamp else {
                            print("🔖 [BookmarksService] Warning: Missing timestamp for document: \(doc.documentID)")
                            return nil
                        }
                        return BookmarkedVideo(id: doc.documentID, timestamp: timestamp.dateValue())
                    }
                    
                    print("🔖 [BookmarksService] State updated - Old count: \(oldCount), New count: \(self.bookmarkedVideos.count)")
                }
        } catch {
            print("🔖 [BookmarksService] Error loading bookmarks: \(error)")
            return
        }
    }
    
    func toggleBookmark(videoId: String) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        print("🔖 [BookmarksService] Toggling bookmark for video: \(videoId)")
        
        let bookmarkRef = db.collection("users")
            .document(userId)
            .collection("bookmarks")
            .document(videoId)
        
        if isBookmarked(videoId: videoId) {
            print("🔖 [BookmarksService] Removing bookmark")
            bookmarkRef.delete()
        } else {
            print("🔖 [BookmarksService] Adding bookmark")
            bookmarkRef.setData(["timestamp": FieldValue.serverTimestamp()])
        }
    }
    
    func isBookmarked(videoId: String) -> Bool {
        return bookmarkedVideos.contains(where: { $0.id == videoId })
    }
}
