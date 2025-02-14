import FirebaseFirestore
import FirebaseAuth

@MainActor
class BookmarksService: ObservableObject {
    private let db = Firestore.firestore()
    @Published var bookmarkedVideos: [BookmarkedVideo] = []
    @Published var bookmarkFolders: [BookmarkFolder] = []
    private var initialLoadCompleted = false
    
    init() {
        Task {
            await loadBookmarkedVideos()
            await loadBookmarkFolders()
        }
    }
    
    func loadBookmarkFolders() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        print("🔖 [BookmarksService] Loading bookmark folders for user: \(userId)")
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("bookmarkFolders")
                .order(by: "timestamp", descending: true)
                .getDocuments()
            
            let documents = snapshot.documents
            print("🔖 [BookmarksService] Initial folders load - Document count: \(documents.count)")
            
            self.bookmarkFolders = documents.compactMap { doc -> BookmarkFolder? in
                let data = doc.data()
                guard let name = data["name"] as? String,
                      let timestamp = data["timestamp"] as? Timestamp,
                      let videoCount = data["videoCount"] as? Int else {
                    print("🔖 [BookmarksService] Warning: Invalid folder data for document: \(doc.documentID)")
                    return nil
                }
                return BookmarkFolder(id: doc.documentID, name: name, timestamp: timestamp.dateValue(), videoCount: videoCount)
            }
            
            // Set up listener for real-time folder updates
            db.collection("users")
                .document(userId)
                .collection("bookmarkFolders")
                .order(by: "timestamp", descending: true)
                .addSnapshotListener { [weak self] querySnapshot, error in
                    guard let self = self else { return }
                    
                    if let error = error {
                        print("🔖 [BookmarksService] Error in folder listener: \(error)")
                        return
                    }
                    
                    guard let documents = querySnapshot?.documents else { return }
                    
                    self.bookmarkFolders = documents.compactMap { doc -> BookmarkFolder? in
                        let data = doc.data()
                        guard let name = data["name"] as? String,
                              let timestamp = data["timestamp"] as? Timestamp,
                              let videoCount = data["videoCount"] as? Int else {
                            return nil
                        }
                        return BookmarkFolder(id: doc.documentID, name: name, timestamp: timestamp.dateValue(), videoCount: videoCount)
                    }
                }
        } catch {
            print("🔖 [BookmarksService] Error loading bookmark folders: \(error)")
        }
    }
    
    func loadBookmarkedVideos() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        print("🔖 [BookmarksService] Loading bookmarked videos for user: \(userId)")
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("videoInteractions")
                .whereField("bookmarked", isGreaterThan: Timestamp(date: Date(timeIntervalSince1970: 0)))
                .order(by: "bookmarked", descending: true)
                .getDocuments()
            
            let documents = snapshot.documents
            print("🔖 [BookmarksService] Initial load - Document count: \(documents.count)")
            
            self.bookmarkedVideos = documents.compactMap { doc -> BookmarkedVideo? in
                let data = doc.data()
                guard let bookmarkedTimestamp = data["bookmarked"] as? Timestamp else {
                    print("🔖 [BookmarksService] Warning: Missing timestamp for document: \(doc.documentID)")
                    return nil
                }
                let folderIds = (data["folders"] as? [String]) ?? []
                return BookmarkedVideo(id: doc.documentID, timestamp: bookmarkedTimestamp.dateValue(), folderIds: folderIds)
            }
            
            print("🔖 [BookmarksService] Initial state set - Bookmarked videos count: \(self.bookmarkedVideos.count)")
            self.initialLoadCompleted = true
            
            // Set up listener for real-time updates
            print("🔖 [BookmarksService] Setting up Firestore listener")
            db.collection("users")
                .document(userId)
                .collection("videoInteractions")
                .whereField("bookmarked", isGreaterThan: Timestamp(date: Date(timeIntervalSince1970: 0)))
                .order(by: "bookmarked", descending: true)
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
                        let data = doc.data()
                        guard let bookmarkedTimestamp = data["bookmarked"] as? Timestamp else {
                            print("🔖 [BookmarksService] Warning: Missing timestamp for document: \(doc.documentID)")
                            return nil
                        }
                        let folderIds = (data["folders"] as? [String]) ?? []
                        return BookmarkedVideo(id: doc.documentID, timestamp: bookmarkedTimestamp.dateValue(), folderIds: folderIds)
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
        print("🔖 [BookmarksService] Current bookmarked videos: \(bookmarkedVideos.map { $0.id })")
        
        let interactionRef = db.collection("users")
            .document(userId)
            .collection("videoInteractions")
            .document(videoId)
        
        if isBookmarked(videoId: videoId) {
            print("🔖 [BookmarksService] Removing bookmark")
            interactionRef.updateData([
                "bookmarked": FieldValue.delete(),
                "folders": FieldValue.delete()
            ])
        } else {
            print("🔖 [BookmarksService] Adding bookmark")
            interactionRef.setData([
                "bookmarked": FieldValue.serverTimestamp()
            ], merge: true)
        }
        
        // Force a refresh of bookmarked videos
        Task {
            await loadBookmarkedVideos()
        }
    }
    
    func createFolder(name: String, videoIds: [String]) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        print("🔖 [BookmarksService] Creating folder '\(name)' with \(videoIds.count) videos")
        
        let folderId = UUID().uuidString
        let batch = db.batch()
        
        // Create folder document
        let folderRef = db.collection("users")
            .document(userId)
            .collection("bookmarkFolders")
            .document(folderId)
        
        batch.setData([
            "name": name,
            "timestamp": FieldValue.serverTimestamp(),
            "videoCount": videoIds.count
        ], forDocument: folderRef)
        
        // Update video interactions
        for videoId in videoIds {
            let interactionRef = db.collection("users")
                .document(userId)
                .collection("videoInteractions")
                .document(videoId)
            
            batch.updateData([
                "folders": FieldValue.arrayUnion([folderId])
            ], forDocument: interactionRef)
        }
        
        try await batch.commit()
    }
    
    func removeVideoFromFolder(videoId: String, folderId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        print("🔖 [BookmarksService] Removing video \(videoId) from folder \(folderId)")
        
        let batch = db.batch()
        
        // Update video interaction
        let interactionRef = db.collection("users")
            .document(userId)
            .collection("videoInteractions")
            .document(videoId)
        
        batch.updateData([
            "folders": FieldValue.arrayRemove([folderId])
        ], forDocument: interactionRef)
        
        // Update folder video count
        let folderRef = db.collection("users")
            .document(userId)
            .collection("bookmarkFolders")
            .document(folderId)
        
        batch.updateData([
            "videoCount": FieldValue.increment(Int64(-1))
        ], forDocument: folderRef)
        
        try await batch.commit()
    }
    
    func deleteFolder(folderId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        print("🔖 [BookmarksService] Deleting folder \(folderId)")
        
        let batch = db.batch()
        
        // Delete folder document
        let folderRef = db.collection("users")
            .document(userId)
            .collection("bookmarkFolders")
            .document(folderId)
        
        batch.deleteDocument(folderRef)
        
        // Remove folder from all videos that reference it
        let interactions = try await db.collection("users")
            .document(userId)
            .collection("videoInteractions")
            .whereField("folders", arrayContains: folderId)
            .getDocuments()
        
        for doc in interactions.documents {
            batch.updateData([
                "folders": FieldValue.arrayRemove([folderId])
            ], forDocument: doc.reference)
        }
        
        try await batch.commit()
    }
    
    func addVideoToFolders(videoId: String, folderIds: [String]) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        print("🔖 [BookmarksService] Adding video \(videoId) to folders: \(folderIds)")
        
        let batch = db.batch()
        let interactionRef = db.collection("users")
            .document(userId)
            .collection("videoInteractions")
            .document(videoId)
        
        // Ensure video is bookmarked and add to folders
        batch.setData([
            "bookmarked": FieldValue.serverTimestamp(),
            "folders": FieldValue.arrayUnion(folderIds)
        ], forDocument: interactionRef, merge: true)
        
        // Update folder video counts
        for folderId in folderIds {
            let folderRef = db.collection("users")
                .document(userId)
                .collection("bookmarkFolders")
                .document(folderId)
            
            batch.updateData([
                "videoCount": FieldValue.increment(Int64(1))
            ], forDocument: folderRef)
        }
        
        try await batch.commit()
    }
    
    func isBookmarked(videoId: String) -> Bool {
        return bookmarkedVideos.contains(where: { $0.id == videoId })
    }
    
    func getFolders(for videoId: String) -> [BookmarkFolder] {
        guard let video = bookmarkedVideos.first(where: { $0.id == videoId }) else { return [] }
        return bookmarkFolders.filter { video.folderIds.contains($0.id) }
    }
}
