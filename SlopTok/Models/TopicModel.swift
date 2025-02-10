import SwiftData
import Foundation

@Model
class Topic {
    var id: UUID
    var name: String
    var weight: Double
    var lastUpdate: Date
    
    init(id: UUID, name: String, weight: Double = 0.5, lastUpdate: Date) {
        self.id = id
        self.name = name
        self.weight = weight
        self.lastUpdate = lastUpdate
    }
}

@Model
class TopicCombination {
    var id: UUID
    var topics: [Topic]
    var weight: Double
    var lastUpdate: Date
    
    init(id: UUID, topics: [Topic], weight: Double = 0.5, lastUpdate: Date) {
        self.id = id
        self.topics = topics
        self.weight = weight
        self.lastUpdate = lastUpdate
    }
}
