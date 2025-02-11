import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class WatchCountCoordinator: ObservableObject {
    static let shared = WatchCountCoordinator()
    private let db = Firestore.firestore()
    
    /// Number of seed videos needed before initial profile creation
    private let seedVideoCount = 10
    
    private init() {}
    
    /// Ensures watch counts document exists and starts monitoring
    func startMonitoring() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let watchCountsRef = db.collection("users")
            .document(userId)
            .collection("watchCounts")
            .document("counts")
            
        // First ensure the document exists
        do {
            let snapshot = try await watchCountsRef.getDocument()
            if !snapshot.exists {
                // Create initial watch counts
                try await watchCountsRef.setData(WatchCounts().firestoreData)
            }
        } catch {
            print("❌ Error initializing watch counts: \(error)")
            return
        }
        
        // Then start monitoring
        watchCountsRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self,
                  let data = snapshot?.data(),
                  let watchCounts = WatchCounts(from: data) else { return }
            
            Task {
                // Check if we need initial profile creation
                if watchCounts.lastProfileUpdate == nil && 
                   watchCounts.videosWatchedSinceLastProfile >= self.seedVideoCount {
                    await self.triggerInitialProfile(userId: userId)
                }
                // // Profile updates will be implemented later
                // else if watchCounts.lastProfileUpdate != nil && 
                //         watchCounts.videosWatchedSinceLastProfile >= 50 {
                //     await self.triggerProfileUpdate(userId: userId)
                // }
            }
        }
    }
    
    /// Triggers initial profile creation after seed videos
    private func triggerInitialProfile(userId: String) async {
        // Reset the counter first to prevent duplicate triggers
        try? await db.collection("users")
            .document(userId)
            .collection("watchCounts")
            .document("counts")
            .updateData([
                "videosWatchedSinceLastProfile": 0,
                "lastProfileUpdate": FieldValue.serverTimestamp()
            ])
            
        await ProfileService.shared.createInitialProfile()
    }
    
    // // Profile updates will be implemented later
    // private func triggerProfileUpdate(userId: String) async {
    //     try? await db.collection("users")
    //         .document(userId)
    //         .collection("watchCounts")
    //         .document("counts")
    //         .updateData([
    //             "videosWatchedSinceLastProfile": 0,
    //             "lastProfileUpdate": FieldValue.serverTimestamp()
    //         ])
    //     
    //     await ProfileService.shared.updateProfile()
    // }
} 