import SwiftUI
import AVKit
import FirebaseAuth

struct ContentView: View {
    let videos = ["man", "skyline", "water"]
    
    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(videos, id: \.self) { video in
                        LoopingVideoView(videoResource: video)
                            .frame(width: UIScreen.main.bounds.width,
                                   height: UIScreen.main.bounds.height)
                            .clipped()
                    }
                }
            }
            .scrollTargetBehavior(.paging)
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: signOut) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.dark)
}
