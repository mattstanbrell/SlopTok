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
                        .foregroundColor(.white)
                        .padding(.leading, 8)
                }
                
                Spacer()
            }
        }
        .frame(width: isExpanded ? UIScreen.main.bounds.width - 32 : 12,
               height: isExpanded ? 40 : 12)
        .background(dotColor.opacity(isExpanded ? 0.3 : 0.2))
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
}
