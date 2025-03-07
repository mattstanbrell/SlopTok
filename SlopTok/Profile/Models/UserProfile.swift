import Foundation

/// Represents a user's profile containing their interests and a descriptive summary
struct UserProfile: Codable {
    /// Collection of user's interests with their weights and examples
    var interests: [Interest]
    
    /// Natural language description of the user's overall profile
    /// Generated by LLM based on interests and their weights
    var description: String
    
    /// When this profile was last updated
    var lastUpdated: Date
    
    /// Creates an empty profile with no interests
    init() {
        self.interests = []
        self.description = ""
        self.lastUpdated = Date()
    }
    
    /// Creates a profile with initial interests
    init(interests: [Interest], description: String) {
        self.interests = interests
        self.description = description
        self.lastUpdated = Date()
    }
} 