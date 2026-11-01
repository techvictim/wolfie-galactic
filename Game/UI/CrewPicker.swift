import SwiftUI

/// Pick who you play as: the seven Wolfie Military crew members.
struct CrewPicker: View {
    let game: Game

    var body: some View {
        let selected = Crew.all[min(max(game.crewIndex, 0), Crew.all.count - 1)]
        ZStack {
            Color(red: 0.04, green: 0.03, blue: 0.12).opacity(0.88)
                .ignoresSafeArea()
            VStack(spacing: UIMetrics.points(14)) {
                Text("Pick your crew")
                    .font(.game(40).weight(.heavy))
                    .foregroundStyle(.white)
                Text(selected.role)
                    .font(.game(17).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: UIMetrics.points(640))
                let columns = Array(repeating: GridItem(.fixed(UIMetrics.points(150)), spacing: UIMetrics.points(14)), count: Game.crewColumns)
                LazyVGrid(columns: columns, spacing: UIMetrics.points(14)) {
                    ForEach(Array(Crew.all.enumerated()), id: \.element.id) { index, member in
                        CrewCard(member: member,
                                 highlighted: index == game.crewIndex,
                                 current: member.id == GameSettings.shared.crew)
                            .onTapGesture { game.tapCrew(index) }
                    }
                }
                Text(game.keyboardMode ? "Arrow keys to look · Return to pick · Esc to go back" : "Pick with \(Btn.cross) · \(Btn.circle) to go back")
                    .font(.game(14).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .oneLine()
            }
            .padding(28)
        }
    }
}

struct CrewCard: View {
    let member: CrewMember
    let highlighted: Bool
    let current: Bool

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let picture = CrewCard.picture(member.id) {
                    picture
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "person.fill")
                        .font(.gameIcon(40, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: UIMetrics.points(116), height: UIMetrics.points(116))
            Text(member.name)
                .font(.game(16).weight(.heavy))
                .foregroundStyle(.white)
                .oneLine()
            Text(current ? "Playing" : " ")
                .font(.game(12).weight(.bold))
                .foregroundStyle(Color(red: 1.0, green: 0.76, blue: 0.1))
        }
        .padding(UIMetrics.points(10))
        .frame(width: UIMetrics.points(150))
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(highlighted ? 0.2 : 0.07)))
        .overlay(RoundedRectangle(cornerRadius: 18)
            .stroke(highlighted ? Color(red: 1.0, green: 0.76, blue: 0.1) : Color.white.opacity(0.12), lineWidth: highlighted ? 3 : 1))
        .scaleEffect(highlighted ? 1.05 : 1)
        .animation(.easeOut(duration: 0.12), value: highlighted)
    }

    @MainActor private static var cache: [String: Image] = [:]

    @MainActor static func picture(_ id: String) -> Image? {
        if let image = cache[id] { return image }
        guard let url = Bundle.main.url(forResource: "crew-\(id)", withExtension: "png") else { return nil }
        #if os(macOS)
        guard let picture = NSImage(contentsOf: url) else { return nil }
        let image = Image(nsImage: picture)
        #else
        guard let picture = UIImage(contentsOfFile: url.path) else { return nil }
        let image = Image(uiImage: picture)
        #endif
        cache[id] = image
        return image
    }
}
