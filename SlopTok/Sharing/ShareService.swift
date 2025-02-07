import Foundation
import FirebaseFirestore
import FirebaseAuth

class ShareService: ObservableObject {
    static let shared = ShareService()
    private let db = Firestore.firestore()
    
    private init() {}
    
    func createShare(videoId: String) async throws -> String {
        let shareId = UUID().uuidString
        let userId = Auth.auth().currentUser?.uid ?? ""
        let userName = Auth.auth().currentUser?.displayName ?? "User"
        
        try await db.collection("shares").document(shareId).setData([
            "videoId": videoId,
            "sharedBy": userId,
            "userName": userName,
            "sharedAt": FieldValue.serverTimestamp()
        ])
        
        return shareId
    }
    
    func getShareInfo(shareId: String) async throws -> (userName: String, timestamp: Date)? {
        let doc = try await db.collection("shares").document(shareId).getDocument()
        guard let data = doc.data() else { return nil }
        
        let userName = data["userName"] as? String ?? "User"
        let timestamp = (data["sharedAt"] as? Timestamp)?.dateValue() ?? Date()
        
        return (userName, timestamp)
    }
    
    func createShareURL(videoId: String, shareId: String) -> URL {
        var components = URLComponents()
        components.scheme = "sloptok"
        components.host = "share"
        components.queryItems = [
            URLQueryItem(name: "shareId", value: shareId),
            URLQueryItem(name: "videoId", value: videoId)
        ]
        
        print("🔗 ShareService - Creating URL components: \(components)")
        
        guard let url = components.url else {
            print("❌ ShareService - Failed to create URL from components")
            return URL(string: "sloptok://error")!
        }
        
        print("🔗 ShareService - Created URL: \(url)")
        return url
    }
}