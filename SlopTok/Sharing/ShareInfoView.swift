import SwiftUI

struct ShareInfoView: View {
    let userName: String
    let timestamp: Date
    @State private var isVisible = true
    
    var body: some View {
        if isVisible {
            HStack {
                Image(systemName: "square.and.arrow.up")
                Text("Shared by \(userName)")
                    .font(.caption)
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .padding()
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                // Hide after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation {
                        isVisible = false
                    }
                }
            }
        }
    }
}