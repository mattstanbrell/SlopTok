import FirebaseFirestore
import FirebaseAuth

@MainActor
class VideoViewService {
    static let shared = VideoViewService()
    private let db = Firestore.firestore()
    
    private init() {}
    
    func markVideoSeen(videoId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let interactionRef = db.collection("users")
            .document(userId)
            .collection("videoInteractions")
            .document(videoId)
        
        do {
            // Use merge: true to not overwrite other fields like likes
            try await interactionRef.setData([
                "last_seen": FieldValue.serverTimestamp()
            ], merge: true)
            
            // Track the video view
            await VideoCountTracker.shared.trackNewVideo(id: videoId)
        } catch {
            print("❌ Error marking video as seen: \(error)")
        }
    }
} 