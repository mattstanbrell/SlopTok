import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class UserVideoService: ObservableObject {
    static let shared = UserVideoService()
    private let db = Firestore.firestore()
    @Published private(set) var userVideos: [UserVideo] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    private init() {}
    
    func loadUserVideos() async {
        isLoading = true
        error = nil
        
        do {
            guard let userId = Auth.auth().currentUser?.uid else {
                isLoading = false
                return
            }
            
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("videos")
                .order(by: "timestamp", descending: true)
                .getDocuments()
            
            userVideos = snapshot.documents.enumerated().map { index, doc in
                let timestamp = (doc.data()["timestamp"] as? Timestamp)?.dateValue() ?? Date()
                return UserVideo(id: doc.documentID, timestamp: timestamp, index: index)
            }
            
            print("📹 UserVideoService - Loaded \(userVideos.count) user videos")
        } catch {
            self.error = error
            print("❌ UserVideoService - Error loading user videos: \(error)")
        }
        
        isLoading = false
    }
    
    func addVideo(_ videoId: String) async {
        do {
            guard let userId = Auth.auth().currentUser?.uid else { return }
            
            try await db.collection("users")
                .document(userId)
                .collection("videos")
                .document(videoId)
                .setData([
                    "timestamp": FieldValue.serverTimestamp()
                ])
            
            // Reload videos to get updated list
            await loadUserVideos()
        } catch {
            self.error = error
            print("❌ UserVideoService - Error adding video: \(error)")
        }
    }
    
    func removeVideo(_ videoId: String) async {
        do {
            guard let userId = Auth.auth().currentUser?.uid else { return }
            
            try await db.collection("users")
                .document(userId)
                .collection("videos")
                .document(videoId)
                .delete()
            
            // Update local state
            userVideos.removeAll { $0.id == videoId }
        } catch {
            self.error = error
            print("❌ UserVideoService - Error removing video: \(error)")
        }
    }
} 