import Foundation

/// Represents a user's interest in a particular topic, with examples and a weight indicating strength of interest
struct Interest: Codable, Identifiable {
    /// Unique identifier for the interest
    let id: String
    
    /// The main topic of interest (e.g., "Mountain Biking", "Rock Climbing", "Trail Running")
    let topic: String
    
    /// Weight indicating strength of interest (0.0-1.0)
    /// - 0.5: Initial weight for new interests
    /// - +0.1: When appearing in new profile
    /// - -0.1: When not appearing in new profile
    /// - 0.0: Interest is removed
    var weight: Double
    
    /// Example activities or aspects of this interest
    /// Used to better understand the specific areas within the topic
    /// 
    /// Examples should be specific and varied, covering different aspects:
    /// - Specific activities (e.g., "downhill trails", "bouldering problems")
    /// - Techniques (e.g., "climbing techniques", "trail maintenance")
    /// - Equipment (e.g., "bike setup", "trail gear")
    /// - Variations (e.g., "technical singletrack", "sport climbing routes")
    ///
    /// Example sets from PRD:
    /// ```
    /// Mountain Biking: ["downhill trails", "bike park jumps", "technical singletrack"]
    /// Rock Climbing: ["bouldering problems", "sport climbing routes", "climbing techniques"]
    /// Trail Running: ["technical trails", "ultrarunning", "trail gear"]
    /// ```
    let examples: [String]
    
    /// When this interest was last updated
    var lastUpdated: Date
    
    /// Creates a new interest with an initial weight of 0.5
    init(topic: String, examples: [String]) {
        self.id = UUID().uuidString
        self.topic = topic
        self.weight = 0.5  // Initial weight as per PRD
        self.examples = examples
        self.lastUpdated = Date()
    }
} 