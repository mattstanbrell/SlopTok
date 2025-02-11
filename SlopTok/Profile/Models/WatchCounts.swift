import Foundation
import FirebaseFirestore

/// Tracks video watching statistics for profile and prompt generation
struct WatchCounts: Codable {
    /// Number of videos watched since last prompt generation
    /// Resets after generating new prompts (at 20 videos)
    var videosWatchedSinceLastPrompt: Int
    
    /// Number of videos watched since last profile update
    /// Resets after updating profile (at 50 videos)
    var videosWatchedSinceLastProfile: Int
    
    /// When prompts were last generated
    var lastPromptGeneration: Date?
    
    /// When profile was last updated
    var lastProfileUpdate: Date?
    
    /// Creates new watch counts starting from zero
    init() {
        self.videosWatchedSinceLastPrompt = 0
        self.videosWatchedSinceLastProfile = 0
        self.lastPromptGeneration = nil
        self.lastProfileUpdate = nil
    }
    
    /// Creates watch counts from Firestore data
    init?(from data: [String: Any]) {
        guard let promptCount = data["videosWatchedSinceLastPrompt"] as? Int,
              let profileCount = data["videosWatchedSinceLastProfile"] as? Int else {
            return nil
        }
        
        self.videosWatchedSinceLastPrompt = promptCount
        self.videosWatchedSinceLastProfile = profileCount
        self.lastPromptGeneration = (data["lastPromptGeneration"] as? Timestamp)?.dateValue()
        self.lastProfileUpdate = (data["lastProfileUpdate"] as? Timestamp)?.dateValue()
    }
    
    /// Converts watch counts to Firestore data
    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "videosWatchedSinceLastPrompt": videosWatchedSinceLastPrompt,
            "videosWatchedSinceLastProfile": videosWatchedSinceLastProfile
        ]
        
        if let promptDate = lastPromptGeneration {
            data["lastPromptGeneration"] = Timestamp(date: promptDate)
        }
        if let profileDate = lastProfileUpdate {
            data["lastProfileUpdate"] = Timestamp(date: profileDate)
        }
        
        return data
    }
} 