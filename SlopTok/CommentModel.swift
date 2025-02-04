import Foundation
import FirebaseFirestore

struct Comment: Identifiable, Codable {
    var id: String
    var text: String
    var authorId: String
    var authorType: String // "user" or "bot"
    var authorName: String
    var authorAvatar: String
    var timestamp: Date
    var parentCommentId: String?
    var likeCount: Int
    var isLikedByCurrentUser: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case text
        case authorId
        case authorType
        case authorName
        case authorAvatar
        case timestamp
        case parentCommentId
        case likeCount
        case isLikedByCurrentUser
    }
    
    init(id: String = UUID().uuidString,
         text: String,
         authorId: String,
         authorType: String,
         authorName: String,
         authorAvatar: String,
         timestamp: Date = Date(),
         parentCommentId: String? = nil,
         likeCount: Int = 0,
         isLikedByCurrentUser: Bool = false) {
        self.id = id
        self.text = text
        self.authorId = authorId
        self.authorType = authorType
        self.authorName = authorName
        self.authorAvatar = authorAvatar
        self.timestamp = timestamp
        self.parentCommentId = parentCommentId
        self.likeCount = likeCount
        self.isLikedByCurrentUser = isLikedByCurrentUser
    }
} 