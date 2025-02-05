import SwiftUI
import FirebaseAuth

class AuthViewModel: ObservableObject {
    @Published var isSignedIn = false
    
    init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.isSignedIn = user != nil  // Changed from null to nil
        }
    }
}
