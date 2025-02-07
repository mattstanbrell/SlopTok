import SwiftUI

struct ShareInfoView: View {
    let userName: String
    let timestamp: Date
    @State private var isVisible = true
    
    var body: some View {
        if isVisible {
            HStack {
                Image(systemName: "person.2")
                Text("Shared by \(userName)")
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .cornerRadius(20)
            .padding()
            .transition(.move(edge: .top).combined(with: .opacity))
            .onAppear {
                // Hide after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        isVisible = false
                    }
                }
            }
        }
    }
}