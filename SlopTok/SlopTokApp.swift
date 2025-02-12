import SwiftUI
import FirebaseCore
import FirebaseStorage
import FirebaseAuth
import GoogleSignIn

@main
struct SlopTokApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @State private var deepLinkVideoId: String?
    @State private var deepLinkShareId: String?
    @State private var deepLinkCounter = 0
    
    init() {
        FirebaseApp.configure()
    }
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            if authViewModel.isSignedIn {
                MainFeedView(initialVideoId: deepLinkVideoId, shareId: deepLinkShareId)
                    .id(deepLinkCounter)
                    .hideHomeIndicator()
                    .onOpenURL { url in
                        print("🔗 Deep Link - URL received: \(url)")
                        handleIncomingURL(url)
                    }
                    .task {
                        // Start monitoring watch counts when signed in
                        await WatchCountCoordinator.shared.startMonitoring()
                    }
            } else {
                AuthView()
                    .hideHomeIndicator()
            }
        }
    }
    
    private func handleIncomingURL(_ url: URL) {
        print("🔗 Deep Link - Handling URL: \(url)")
        print("🔗 Deep Link - Scheme: \(url.scheme ?? "nil")")
        
        guard url.scheme == "sloptok" else {
            print("❌ Deep Link - Invalid scheme")
            return
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let shareId = components.queryItems?.first(where: { $0.name == "shareId" })?.value,
              let videoId = components.queryItems?.first(where: { $0.name == "videoId" })?.value else {
            print("❌ Deep Link - Missing query parameters")
            print("🔗 Deep Link - URL Components: \(String(describing: URLComponents(url: url, resolvingAgainstBaseURL: true)))")
            return
        }
        
        print("✅ Deep Link - Valid share URL found")
        print("🔗 Deep Link - ShareID: \(shareId)")
        print("🔗 Deep Link - VideoID: \(videoId)")
        
        deepLinkVideoId = videoId
        deepLinkShareId = shareId
        deepLinkCounter += 1
        
        print("✅ Deep Link - State updated: shareId=\(deepLinkShareId ?? "nil"), videoId=\(deepLinkVideoId ?? "nil"), counter=\(deepLinkCounter)")
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication,
                    open url: URL,
                    options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}
