import FirebaseFirestore
import FirebaseAuth

@MainActor
class PromptLineageService {
    static let shared = PromptLineageService()
    private let db = Firestore.firestore()
    
    // MARK: - Data Structures
    
    struct PromptAttempt: Codable {
        let id: String               // The video ID
        let prompt: String           // The actual prompt text
        let parentId: String?        // Parent prompt ID if this was a mutation/crossover
        let timestamp: Date          // When this attempt was made
        let wasLiked: Bool          // Whether the user liked this video
        let attemptNumber: Int      // Which attempt this was for the parent (1, 2, or 3)
        let style: String           // The style used
        let targetLength: Int       // Target video length
    }
    
    struct PromptLineage {
        let rootId: String          // Original successful prompt ID
        let attempts: [PromptAttempt] // All attempts derived from this root
        
        var failedAttempts: [PromptAttempt] {
            attempts.filter { !$0.wasLiked }
        }
        
        var successfulAttempts: [PromptAttempt] {
            attempts.filter { $0.wasLiked }
        }
        
        var shouldAbandon: Bool {
            // If we have 3 failed attempts with no successes, abandon this branch
            let failedCount = failedAttempts.count
            let successCount = successfulAttempts.count
            return failedCount >= 3 && successCount == 0
        }
        
        var shouldTryAgain: Bool {
            // If we have some successes or fewer than 3 failures, keep trying
            return !shouldAbandon && failedAttempts.count < 3
        }
    }
    
    // MARK: - Storage Methods
    
    func recordAttempt(videoId: String, prompt: String, parentId: String?, style: String, targetLength: Int) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Get the attempt number if this has a parent
        var attemptNumber = 1
        if let parentId = parentId {
            let attempts = try await fetchAttempts(forParent: parentId)
            attemptNumber = attempts.count + 1
        }
        
        let attempt = PromptAttempt(
            id: videoId,
            prompt: prompt,
            parentId: parentId,
            timestamp: Date(),
            wasLiked: false,  // Initially false, updated when liked
            attemptNumber: attemptNumber,
            style: style,
            targetLength: targetLength
        )
        
        try await db.collection("users")
            .document(userId)
            .collection("promptAttempts")
            .document(videoId)
            .setData(attempt.dictionary)
    }
    
    func updateAttemptLikeStatus(videoId: String, wasLiked: Bool) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        try await db.collection("users")
            .document(userId)
            .collection("promptAttempts")
            .document(videoId)
            .setData(["wasLiked": wasLiked], merge: true)
    }
    
    func fetchAttempts(forParent parentId: String) async throws -> [PromptAttempt] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("promptAttempts")
            .whereField("parentId", isEqualTo: parentId)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: PromptAttempt.self)
        }
    }
    
    func fetchLineage(forRootId rootId: String) async throws -> PromptLineage {
        guard let userId = Auth.auth().currentUser?.uid else { 
            return PromptLineage(rootId: rootId, attempts: [])
        }
        
        // First get all attempts that have this root as their parent
        var allAttempts: [PromptAttempt] = []
        var idsToCheck = [rootId]
        
        // Recursively fetch all descendants
        while !idsToCheck.isEmpty {
            let currentId = idsToCheck.removeFirst()
            let attempts = try await fetchAttempts(forParent: currentId)
            allAttempts.append(contentsOf: attempts)
            // Add any successful attempts to check for their children
            idsToCheck.append(contentsOf: attempts.filter { $0.wasLiked }.map { $0.id })
        }
        
        return PromptLineage(rootId: rootId, attempts: allAttempts)
    }
    
    func fetchAllLineages() async throws -> [PromptLineage] {
        guard let userId = Auth.auth().currentUser?.uid else { return [] }
        
        // Get all root prompts (those without parents)
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("promptAttempts")
            .whereField("parentId", isEqualTo: NSNull())
            .getDocuments()
        
        let rootIds = snapshot.documents.map { $0.documentID }
        
        // Fetch full lineage for each root
        var lineages: [PromptLineage] = []
        for rootId in rootIds {
            let lineage = try await fetchLineage(forRootId: rootId)
            lineages.append(lineage)
        }
        
        return lineages
    }
}

// MARK: - Codable Helper

private extension Encodable {
    var dictionary: [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }
} 