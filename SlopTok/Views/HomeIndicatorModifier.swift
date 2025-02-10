import SwiftUI

class HomeIndicatorViewController: UIViewController {
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }
}

struct HomeIndicatorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(HostingControllerSetter())
    }
    
    private struct HostingControllerSetter: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> HomeIndicatorViewController {
            HomeIndicatorViewController()
        }
        
        func updateUIViewController(_ uiViewController: HomeIndicatorViewController, context: Context) {
            uiViewController.setNeedsUpdateOfHomeIndicatorAutoHidden()
        }
    }
}

extension View {
    func hideHomeIndicator() -> some View {
        modifier(HomeIndicatorModifier())
    }
} 