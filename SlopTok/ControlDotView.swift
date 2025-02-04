import SwiftUI
import FirebaseAuth

struct ControlDotView: View {
    @Binding var isExpanded: Bool
    @State private var showProfile = false
    let userName: String
    let dotColor: Color
    @ObservedObject var likesService: LikesService
    
    var body: some View {
        HStack {
            if isExpanded {
                Button(action: { showProfile = true }) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(dotColor)
                        .padding(.leading, 8)
                }
                
                Spacer()
                
                Button(action: signOut) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundColor(dotColor)
                }
                .padding(.trailing, 8)
            }
        }
        .frame(width: isExpanded ? UIScreen.main.bounds.width - 32 : 12,
               height: isExpanded ? 40 : 12)
        .background(dotColor.opacity(isExpanded ? 0.4 : 0.3))
        .clipShape(Capsule())
        .padding(20)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfileView(userName: userName, likesService: likesService)
                .presentationDragIndicator(.visible) // Shows the grab handle
        }
    }
    
    private func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
}
