import SwiftUI

/// One card of the Red Glitch story: who's talking, their picture, and what they say.
struct StoryView: View {
    let game: Game
    private let red = Color(red: 1, green: 0.17, blue: 0.23)
    private let amber = Color(red: 1.0, green: 0.76, blue: 0.1)

    var body: some View {
        let card = game.storyCard
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.02, blue: 0.05).opacity(0.94), Color(red: 0.03, green: 0.02, blue: 0.1).opacity(0.94)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: UIMetrics.points(18)) {
                Text("The Red Glitch")
                    .font(.game(22).weight(.heavy))
                    .foregroundStyle(red)
                    .textCase(.uppercase)
                    .tracking(3)
                HStack(alignment: .center, spacing: UIMetrics.points(28)) {
                    Group {
                        if let picture = GamePicture.named(card.picture) {
                            picture.resizable().interpolation(.high).scaledToFit()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: UIMetrics.points(220), height: UIMetrics.points(220))
                    .background(Circle().fill(Color.white.opacity(0.06)))
                    VStack(alignment: .leading, spacing: 10) {
                        Text(card.who)
                            .font(.game(20).weight(.heavy))
                            .foregroundStyle(amber)
                        Text(card.text)
                            .font(.game(30).weight(.bold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: UIMetrics.points(560), alignment: .leading)
                }
                HStack(spacing: 8) {
                    ForEach(0..<Game.story.count, id: \.self) { i in
                        Capsule()
                            .fill(i == game.storyIndex ? red : Color.white.opacity(0.25))
                            .frame(width: i == game.storyIndex ? 26 : 10, height: 10)
                    }
                }
                Text(game.keyboardMode ? "Return for next · Esc to skip" : "\(Btn.cross) for next · \(Btn.circle) to skip")
                    .font(.game(15).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(32)
        }
        .contentShape(Rectangle())
        .onTapGesture { game.nextStoryCard() }
        .animation(.easeOut(duration: 0.2), value: game.storyIndex)
    }
}

/// Pictures from Resources, by file name.
@MainActor
enum GamePicture {
    private static var cache: [String: Image] = [:]

    static func named(_ name: String) -> Image? {
        if let image = cache[name] { return image }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        #if os(macOS)
        guard let picture = NSImage(contentsOf: url) else { return nil }
        let image = Image(nsImage: picture)
        #else
        guard let picture = UIImage(contentsOfFile: url.path) else { return nil }
        let image = Image(uiImage: picture)
        #endif
        cache[name] = image
        return image
    }
}

extension Game {
    /// The sky colour of the planet you're on (or about to land on).
    var planetSkyColor: Color {
        let id = place == .space ? space.planetID : planet.id
        let c = BlockRegistry.parseHex(PlanetCatalog.shared.planet(id: id)?.sky ?? planet.sky)
        return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }
}
