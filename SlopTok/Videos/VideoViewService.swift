import FirebaseFirestore
import FirebaseAuth

@MainActor
class VideoViewService {
    static let shared = VideoViewService()
    private let db = Firestore.firestore()
    
    private init() {}
    
    /// Records a video view, updating watch counts if it's the first time watching
    func markVideoSeen(videoId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let interactionRef = db.collection("users")
            .document(userId)
            .collection("videoInteractions")
            .document(videoId)
            
        do {
            // Check if this is first watch
            let doc = try await interactionRef.getDocument()
            let isFirstWatch = !doc.exists
            
            // Batch write for consistency
            let batch = db.batch()
            
            // 1. Update video interaction
            batch.setData([
                "last_seen": FieldValue.serverTimestamp(),
                "isFirstWatch": false
            ], forDocument: interactionRef, merge: true)
            
            // 2. If first watch, increment watch counts
            if isFirstWatch {
                let watchCountsRef = db.collection("users")
                    .document(userId)
                    .collection("watchCounts")
                    .document("counts")
                
                batch.updateData([
                    "videosWatchedSinceLastProfile": FieldValue.increment(Int64(1))
                ], forDocument: watchCountsRef)
            }
            
            try await batch.commit()
            
            if isFirstWatch {
                print("✅ Marked video \(videoId) as seen (first watch)")
            } else {
                print("✅ Marked video \(videoId) as seen (repeat watch)")
            }
            
        } catch {
            print("❌ Error marking video as seen: \(error)")
        }
    }
} 