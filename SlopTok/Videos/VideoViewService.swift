import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage

@MainActor
class VideoViewService {
    static let shared = VideoViewService()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
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
            
            // If first watch, get the video prompt from Storage metadata
            var promptData: [String: Any] = [:]
            if isFirstWatch {
                let videoRef = storage.reference().child("videos/seed/\(videoId).mp4")
                let metadata = try await videoRef.getMetadata()
                if let prompt = metadata.customMetadata?["prompt"] {
                    promptData["prompt"] = prompt
                }
            }
            
            // Batch write for consistency
            let batch = db.batch()
            
            // 1. Update video interaction
            var interactionData: [String: Any] = [
                "last_seen": FieldValue.serverTimestamp(),
                "isFirstWatch": false
            ]
            if !promptData.isEmpty {
                interactionData.merge(promptData) { (_, new) in new }
            }
            batch.setData(interactionData, forDocument: interactionRef, merge: true)
            
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