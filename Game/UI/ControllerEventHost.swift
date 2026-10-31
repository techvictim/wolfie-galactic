#if os(tvOS)
import SwiftUI
import GameController
import UIKit

/// Apple TV only: hosts the game inside a GCEventViewController.
///
/// Without this, tvOS treats a game controller's B / Circle button like the remote's
/// Menu button and leaves the app. With `systemHandlesController` off, every button
/// press goes to the game instead (the game reads controllers directly).
struct ControllerEventHost<Content: View>: UIViewControllerRepresentable {
    let systemHandlesController: Bool
    let content: Content

    init(systemHandlesController: Bool, @ViewBuilder content: () -> Content) {
        self.systemHandlesController = systemHandlesController
        self.content = content()
    }

    func makeUIViewController(context: Context) -> GCEventViewController {
        let controller = GCEventViewController()
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.view.frame = controller.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.addChild(host)
        controller.view.addSubview(host.view)
        host.didMove(toParent: controller)
        controller.controllerUserInteractionEnabled = systemHandlesController
        context.coordinator.host = host
        return controller
    }

    func updateUIViewController(_ controller: GCEventViewController, context: Context) {
        controller.controllerUserInteractionEnabled = systemHandlesController
        context.coordinator.host?.rootView = content
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var host: UIHostingController<Content>?
    }
}
#endif
