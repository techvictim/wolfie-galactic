import SwiftUI

@main
struct WolfieGalacticApp: App {
    @State private var game = Game()

    var body: some Scene {
        WindowGroup {
            #if os(tvOS)
            // While playing, controller buttons belong to the game. Only on the title screen
            // do they go to the Apple TV, so B or Menu there returns to the home screen.
            ControllerEventHost(systemHandlesController: game.screen == .title) {
                GameView(game: game)
            }
            .ignoresSafeArea()
            #else
            GameView(game: game)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 800)
        #endif
    }
}
