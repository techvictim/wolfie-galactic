import SwiftUI
import RealityKit
import simd
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct GameView: View {
    let game: Game
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            RealityView { content in
                #if os(iOS)
                content.camera = .virtual
                #endif
                content.add(game.root)
                let running = game
                running.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                    MainActor.assumeIsolated {
                        running.update(dt: event.deltaTime)
                    }
                }
            }
            .ignoresSafeArea()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { game.viewSize = $0 }

            if game.screen == .playing && game.travelText == nil {
                NameTagsView(game: game)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if game.screen == .playing || game.screen == .starMap {
                HUDView(game: game)
                    .transition(.opacity)
            }

            if game.showHelp && (game.screen == .playing || game.screen == .starMap) {
                HelpCard(game: game)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if game.screen == .title {
                TitleView(game: game)
                    .transition(.opacity)
            }

            if game.screen == .paused || game.screen == .settings || game.screen == .friends {
                MenuPanel(game: game)
                    .transition(.opacity)
            }

            if game.screen == .controls {
                ControlsPanel(game: game)
                    .transition(.opacity)
            }

            if game.screen == .critterBook {
                CritterBookView(game: game)
                    .transition(.opacity)
            }

            if game.entryGlow {
                EntryGlow()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if game.warpGlow > 0.01 {
                RadialGradient(colors: [Color.white.opacity(0.0), Color(red: 0.55, green: 0.8, blue: 1).opacity(Double(game.warpGlow) * 0.55)],
                               center: .center, startRadius: 80, endRadius: 900)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if game.hurtFlash {
                RadialGradient(colors: [.clear, Color.red.opacity(0.45)], center: .center, startRadius: 120, endRadius: 900)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if game.starMapOpen {
                StarMapView(game: game)
                    .transition(.opacity)
            }

            if let text = game.travelText {
                TravelView(text: text)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: game.screen)
        .animation(.easeInOut(duration: 0.45), value: game.travelText)
        .animation(.easeOut(duration: 0.2), value: game.hurtFlash)
        .animation(.easeOut(duration: 0.2), value: game.showHelp)
        .animation(.easeInOut(duration: 0.4), value: game.entryGlow)
        .background(Color.black)
        .onAppear {
            Sound.shared.start()
            game.input.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.save() }
        }
    }
}

struct HUDView: View {
    let game: Game

    var body: some View {
        ZStack {
            Crosshair(laser: game.laserSelected)
                .allowsHitTesting(false)

            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                    if game.showHearts {
                        HeartsView(hearts: game.hearts, maxHearts: Game.maxHearts)
                    }
                    if let summary = game.togetherSummary {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2.fill")
                            Text(summary)
                        }
                        .font(.game(15).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .allowsHitTesting(false)
                    }
                    }
                    Spacer()
                    // Every control, behind one button: Create/View on a controller, ? on a keyboard.
                    HStack(spacing: 6) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.gameIcon(18, weight: .bold))
                        Text(game.keyboardMode ? "?" : "⧉")
                            .font(.game(14).weight(.heavy))
                    }
                    .foregroundStyle(.white.opacity(game.showHelp ? 1 : 0.8))
                    .padding(.horizontal, UIMetrics.points(12))
                    .frame(height: UIMetrics.points(52))
                    .background(Capsule().fill(Color.black.opacity(game.showHelp ? 0.65 : 0.4)))
                    .contentShape(Capsule())
                    .onTapGesture { game.showHelp.toggle() }
                    .accessibilityLabel("Controls")
                    Image(systemName: "pause.fill")
                        .font(.gameIcon(22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: UIMetrics.points(52), height: UIMetrics.points(52))
                        .background(Circle().fill(Color.black.opacity(0.4)))
                        .contentShape(Circle())
                        .onTapGesture { game.handleBackButton() }
                        .accessibilityLabel("Pause")
                }
                .padding(.top, 16)
                .padding(.horizontal, 20)
                Spacer()
            }

            VStack(spacing: 12) {
                if game.pointerFree {
                    Text("Click to look around")
                        .font(.game(20).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                        .padding(.top, 70)
                        .allowsHitTesting(false)
                }
                if game.flying {
                    HStack(spacing: 8) {
                        Image(systemName: "airplane")
                        Text("Flying")
                    }
                    .font(.game(15).weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color(red: 0.37, green: 0.94, blue: 1.0).opacity(0.3)))
                    .padding(.top, 20)
                    .allowsHitTesting(false)
                }
                if !game.message.isEmpty {
                    Text(game.message)
                        .font(.game(17))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(.top, 20)
                }
                Spacer()
                if let prompt = game.petPrompt {
                    HStack(spacing: 10) {
                        ButtonBadge(letter: game.keyboardMode ? "Right-click" : "LT")
                        Text(prompt)
                            .font(.game(20).weight(.bold))
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.65))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .allowsHitTesting(false)
                } else if let kind = game.dockPrompt, game.place == .space, !game.starMapOpen {
                    HStack(spacing: 10) {
                        ButtonBadge(letter: game.keyboardMode ? "F" : "Y")
                        Text("Switch to the \(kind.name)")
                            .font(.game(20).weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .allowsHitTesting(false)
                } else if let kind = game.nearVehicle, !game.starMapOpen {
                    HStack(spacing: 10) {
                        ButtonBadge(letter: game.keyboardMode ? "F" : "Y")
                        Text(kind.isShip ? "Fly the \(kind.name)" : "Drive the \(kind.name)")
                            .font(.game(20).weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .contentShape(Capsule())
                    .onTapGesture { game.boardFromButton() }
                }
                if game.driving == nil {
                    HotbarView(game: game)
                        .padding(.bottom, 20)
                } else {
                    Spacer().frame(height: 20)
                }
            }
        }
        .oneLine()
    }
}

/// The controls for what you're doing right now: on foot, in the rover, or in the starship.
/// Opened and closed with the help button so the screen stays clear while playing.
struct HelpCard: View {
    let game: Game

    var body: some View {
        let kb = game.keyboardMode
        let rows = game.place == .space ? HelpCard.spaceRows(keyboard: kb) : HelpCard.rows(driving: game.driving, flying: game.flying, keyboard: kb)
        VStack(alignment: .leading, spacing: UIMetrics.points(10)) {
            HStack {
                Text(title)
                    .font(.game(24).weight(.heavy))
                Spacer()
                Text(kb ? "? to close" : "⧉ to close")
                    .font(.game(13).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            ForEach(rows, id: \.1) { row in
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        ForEach(row.0, id: \.self) { ButtonBadge(letter: $0) }
                    }
                    .frame(minWidth: UIMetrics.points(110), alignment: .leading)
                    Text(row.1)
                        .font(.game(17).weight(.semibold))
                }
            }
        }
        .foregroundStyle(.white)
        .oneLine()
        .padding(UIMetrics.points(22))
        .frame(maxWidth: UIMetrics.points(460))
        .background(RoundedRectangle(cornerRadius: 22).fill(Color(red: 0.05, green: 0.04, blue: 0.14).opacity(0.86)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { game.showHelp = false }
    }

    private var title: String {
        if game.place == .space { return "Flying in space" }
        switch game.driving {
        case .some(let kind) where !kind.isShip: return "Driving the \(kind.name)"
        case .some(let kind): return "Flying the \(kind.name)"
        case nil: return "Controls"
        }
    }

    static func spaceRows(keyboard kb: Bool) -> [([String], String)] {
        [
            ([kb ? "Mouse" : "R stick"], "Steer: left, right, up, down"),
            ([kb ? "W  S" : "L stick"], "Faster and slower"),
            ([kb ? "Space" : "A", kb ? "Shift" : "B"], "Rise and sink"),
            ([kb ? "Click" : "RT"], "Fire lasers"),
            ([kb ? "M" : "X"], "Hyperspace to another planet"),
            ([kb ? "F" : "Y"], "Swap ships at the spaceport"),
            ([], "Fly into the planet to land")
        ]
    }

    static func rows(driving: VehicleKind?, flying: Bool, keyboard kb: Bool) -> [([String], String)] {
        switch driving {
        case .starship, .comet, .hauler, .zoomer:
            return [
                ([kb ? "Mouse" : "R stick"], "Steer: left, right, up, down"),
                ([kb ? "W" : "L stick ↑"], "Faster"),
                ([kb ? "S" : "L stick ↓"], "Slower, then backwards"),
                ([kb ? "Space" : "A", kb ? "Shift" : "B"], "Rise and sink"),
                ([kb ? "Click" : "RT"], "Fire lasers"),
                ([kb ? "M" : "X"], "Star map: fly to a planet"),
                ([kb ? "F" : "Y"], "Get out"),
                ([], "Fly up and up to reach space")
            ]
        case .rover, .buggy, .hoverbike:
            return [
                ([kb ? "W A S D" : "L stick"], "Drive and steer"),
                ([kb ? "Mouse" : "R stick"], "Look around"),
                ([kb ? "Space" : "A"], "Hop"),
                ([kb ? "Click" : "RT"], "Fire lasers"),
                ([kb ? "H" : "X"], "Honk!"),
                ([kb ? "F" : "Y"], "Get out")
            ]
        case nil:
            var rows: [([String], String)] = [
                ([kb ? "W A S D" : "L stick"], "Walk"),
                ([kb ? "Mouse" : "R stick"], "Look around"),
                ([kb ? "Space" : "A"], flying ? "Fly up" : "Jump · double-tap to fly"),
            ]
            if flying { rows.append(([kb ? "Shift" : "B"], "Fly down · land on the ground")) }
            rows += [
                ([kb ? "Click" : "RT"], "Break blocks · fire the laser"),
                ([kb ? "Right-click" : "LT"], "Place a block · pet a critter"),
                ([kb ? "Q  E" : "LB  RB"], "Pick from the hotbar"),
                ([kb ? "F" : "Y"], "Get in a vehicle or ship"),
                ([kb ? "Esc" : "≡"], "Pause, Critter Book, settings")
            ]
            return rows
        }
    }
}

/// Coming down through an atmosphere: orange heat around the edges, flickering.
struct EntryGlow: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let flicker = 0.75 + 0.25 * sin(t * 37) * sin(t * 13)
            RadialGradient(
                colors: [Color.white.opacity(0.08), Color(red: 1, green: 0.55, blue: 0.15).opacity(0.55 * flicker), Color(red: 1, green: 0.2, blue: 0.05).opacity(0.85 * flicker)],
                center: .center, startRadius: 60, endRadius: 950
            )
        }
    }
}

/// Friends' names, floating over their heads.
struct NameTagsView: View {
    let game: Game

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(game.nameTags) { tag in
                let c = Avatars.color(tag.color)
                Text(tag.name)
                    .font(.game(15).weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z)).opacity(0.8)))
                    .overlay(Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1.5))
                    .fixedSize()
                    .position(x: tag.x, y: tag.y)
            }
        }
    }
}

/// Hearts left, when Danger is on.
struct HeartsView: View {
    let hearts: Int
    let maxHearts: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<maxHearts, id: \.self) { i in
                Image(systemName: i < hearts ? "heart.fill" : "heart")
                    .font(.gameIcon(22, weight: .bold))
                    .foregroundStyle(i < hearts ? Color(red: 1, green: 0.32, blue: 0.48) : Color.white.opacity(0.5))
                    .scaleEffect(i < hearts ? 1 : 0.85)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.4)))
        .animation(.spring(duration: 0.3), value: hearts)
        .allowsHitTesting(false)
        .accessibilityLabel("\(hearts) of \(maxHearts) hearts")
    }
}

// MARK: - Critter book

/// Every critter in the galaxy: the ones you've met, and shadows of the ones still out there.
struct CritterBookView: View {
    let game: Game

    var body: some View {
        let kinds = CritterCatalog.shared.kinds
        ZStack {
            Color(red: 0.04, green: 0.03, blue: 0.12).opacity(0.88)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Critter book")
                    .font(.game(40).weight(.heavy))
                    .foregroundStyle(.white)
                Text("\(game.foundCritters.count) of \(kinds.count) found · look at a critter and press \(game.keyboardMode ? "right-click" : "LT") to make friends")
                    .font(.game(16).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .oneLine()
                HStack(alignment: .top, spacing: UIMetrics.points(14)) {
                    ForEach(kinds) { kind in
                        CritterCard(kind: kind, found: game.foundCritters.contains(kind.id))
                    }
                }
                MenuRow(game: game, item: .back, selected: true, big: false)
                    .frame(maxWidth: UIMetrics.points(240))
            }
            .padding(28)
        }
    }
}

struct CritterCard: View {
    let kind: CritterKind
    let found: Bool

    var body: some View {
        let planets = kind.planets.compactMap { id in PlanetCatalog.shared.planets.first { $0.id == id }?.name }
        VStack(spacing: 8) {
            Group {
                if let picture = CritterCard.picture(kind.id) {
                    picture
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .colorMultiply(found ? .white : .black)
                        .opacity(found ? 1 : 0.55)
                } else {
                    Image(systemName: "questionmark")
                        .font(.gameIcon(40, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: UIMetrics.points(120), height: UIMetrics.points(120))
            Text(found ? kind.name : "???")
                .font(.game(18).weight(.heavy))
                .foregroundStyle(.white)
                .oneLine()
            Text(kind.isGrumpy ? "Comes out when Danger is on" : (planets.first.map { "Lives on \($0)" } ?? ""))
                .font(.game(12).weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.6))
                .oneLine()
            Text(found ? kind.fact : (kind.isGrumpy ? "Zap one with your laser to send it home." : "Not found yet. Go exploring!"))
                .font(.game(13))
                .foregroundStyle(Color.white.opacity(found ? 0.9 : 0.55))
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
                .frame(height: UIMetrics.points(70), alignment: .top)
        }
        .padding(UIMetrics.points(12))
        .frame(width: UIMetrics.points(172))
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(found ? 0.12 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(found ? Color(red: 1.0, green: 0.71, blue: 0.28).opacity(0.8) : Color.white.opacity(0.12), lineWidth: found ? 2 : 1))
    }

    @MainActor private static var cache: [String: Image] = [:]

    @MainActor static func picture(_ id: String) -> Image? {
        if let image = cache[id] { return image }
        guard let url = Bundle.main.url(forResource: "critter-\(id)", withExtension: "png") else { return nil }
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

struct Crosshair: View {
    var laser = false

    var body: some View {
        ZStack {
            Rectangle().frame(width: 3, height: 20)
            Rectangle().frame(width: 20, height: 3)
            if laser {
                Circle().stroke(lineWidth: 2).frame(width: 30, height: 30)
            }
        }
        .foregroundStyle(laser ? Color(red: 1, green: 0.45, blue: 0.9) : Color.white.opacity(0.9))
        .shadow(color: .black.opacity(0.5), radius: 1)
    }
}

/// Six big picture slots. The chosen one grows and gets an amber outline; its name is spoken.
struct HotbarView: View {
    let game: Game
    private let amber = Color(red: 1.0, green: 0.71, blue: 0.28)

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(game.hotbar.enumerated()), id: \.offset) { slot, blockID in
                let selected = slot == game.hotbarIndex
                Group {
                    if blockID == B.laser {
                        LaserIcon()
                    } else {
                        BlockIcon(rgb: BlockRegistry.shared.rgb(blockID))
                    }
                }
                    .frame(width: UIMetrics.points(44), height: UIMetrics.points(44))
                    .padding(9)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.black.opacity(selected ? 0.55 : 0.32))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(selected ? amber : Color.white.opacity(0.25), lineWidth: selected ? 4 : 1)
                    )
                    .scaleEffect(selected ? 1.12 : 1)
                    .onTapGesture { game.selectSlot(slot) }
                    .accessibilityLabel(BlockRegistry.shared.name(blockID))
            }
        }
        .animation(.spring(duration: 0.2), value: game.hotbarIndex)
    }
}

/// A little toy-voxel cube drawn with three shaded faces.
struct BlockIcon: View {
    let rgb: SIMD3<Float>

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            var top = Path()
            top.move(to: pt(0.5, 0.06))
            top.addLine(to: pt(0.94, 0.29))
            top.addLine(to: pt(0.5, 0.52))
            top.addLine(to: pt(0.06, 0.29))
            top.closeSubpath()
            var left = Path()
            left.move(to: pt(0.06, 0.29))
            left.addLine(to: pt(0.5, 0.52))
            left.addLine(to: pt(0.5, 0.96))
            left.addLine(to: pt(0.06, 0.73))
            left.closeSubpath()
            var right = Path()
            right.move(to: pt(0.94, 0.29))
            right.addLine(to: pt(0.5, 0.52))
            right.addLine(to: pt(0.5, 0.96))
            right.addLine(to: pt(0.94, 0.73))
            right.closeSubpath()
            context.fill(top, with: .color(shade(1.0)))
            context.fill(left, with: .color(shade(0.74)))
            context.fill(right, with: .color(shade(0.88)))
        }
    }

    private func shade(_ k: Float) -> Color {
        let lifted = rgb + (SIMD3<Float>(repeating: 1) - rgb) * FaceShade.lift
        let c = simd_min(lifted * k, SIMD3<Float>(repeating: 1))
        return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }
}

/// The laser blaster's hotbar picture: a little pink ray gun.
struct LaserIcon: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let pink = Color(red: 1, green: 0.31, blue: 0.85)
            let dark = Color(red: 0.24, green: 0.29, blue: 0.36)
            let barrel = Path(roundedRect: CGRect(x: w * 0.12, y: h * 0.3, width: w * 0.6, height: h * 0.24), cornerRadius: h * 0.08)
            let grip = Path(roundedRect: CGRect(x: w * 0.18, y: h * 0.48, width: w * 0.18, height: h * 0.34), cornerRadius: h * 0.05)
            let tip = Path(ellipseIn: CGRect(x: w * 0.68, y: h * 0.32, width: w * 0.2, height: h * 0.2))
            var ray = Path()
            ray.move(to: CGPoint(x: w * 0.86, y: h * 0.42))
            ray.addLine(to: CGPoint(x: w * 1.0, y: h * 0.42))
            context.fill(grip, with: .color(dark))
            context.fill(barrel, with: .color(Color(red: 0.72, green: 0.76, blue: 0.8)))
            context.fill(tip, with: .color(pink))
            context.stroke(ray, with: .color(pink), lineWidth: h * 0.07)
        }
    }
}

/// A round controller-style button letter.
struct ButtonBadge: View {
    let letter: String

    var body: some View {
        Text(letter)
            .font(.game(17).weight(.heavy))
            .foregroundStyle(.black)
            .padding(.horizontal, letter.count > 1 ? 8 : 0)
            .frame(minWidth: UIMetrics.points(30), minHeight: UIMetrics.points(30))
            .background(Capsule().fill(Color(red: 1.0, green: 0.71, blue: 0.28)))
    }
}

/// Choose a planet or moon to fly to.
struct StarMapView: View {
    let game: Game
    private let amber = Color(red: 1.0, green: 0.71, blue: 0.28)

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.03, blue: 0.12).opacity(0.88)
                .ignoresSafeArea()
                .onTapGesture { game.closeStarMap() }

            VStack(spacing: 28) {
                Text("Where to?")
                    .font(.game(40).weight(.heavy))
                    .foregroundStyle(.white)

                HStack(spacing: 28) {
                    ForEach(Array(game.planets.enumerated()), id: \.offset) { index, planet in
                        let selected = index == game.starMapSelection
                        let here = planet.id == game.planet.id
                        VStack(spacing: 12) {
                            PlanetBall(colors: planet.mapColors)
                                .frame(width: UIMetrics.points(120), height: UIMetrics.points(120))
                            Text(planet.name)
                                .font(.game(22).weight(.bold))
                                .foregroundStyle(.white)
                            Text(here ? "You are here" : planet.kind)
                                .font(.game(15).weight(.semibold))
                                .foregroundStyle(here ? amber : Color.white.opacity(0.7))
                            if planet.gravity < 15 {
                                Text("Low gravity: big jumps")
                                    .font(.game(13))
                                    .foregroundStyle(Color.white.opacity(0.7))
                            }
                        }
                        .padding(20)
                        .frame(width: UIMetrics.points(210))
                        .background(
                            RoundedRectangle(cornerRadius: 22)
                                .fill(Color.white.opacity(selected ? 0.12 : 0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(selected ? amber : Color.white.opacity(0.15), lineWidth: selected ? 4 : 1)
                        )
                        .scaleEffect(selected ? 1.06 : 1)
                        .onTapGesture {
                            game.selectStarMapItem(index)
                            game.travel(to: index)
                        }
                    }
                }

                HStack(spacing: 22) {
                    HStack(spacing: 8) { ButtonBadge(letter: "◀▶"); Text("Choose") }
                    HStack(spacing: 8) { ButtonBadge(letter: game.keyboardMode ? "⏎" : "A"); Text(game.place == .space ? "Hyperspace" : "Fly") }
                    HStack(spacing: 8) { ButtonBadge(letter: game.keyboardMode ? "esc" : "B"); Text("Stay here") }
                }
                .font(.game(17))
                .foregroundStyle(Color.white.opacity(0.85))
            }
            .padding(24)
            .animation(.spring(duration: 0.25), value: game.starMapSelection)
        }
    }
}

/// A planet drawn as a shaded ball with bands, from two colours.
struct PlanetBall: View {
    let colors: [String]

    var body: some View {
        let a = color(0)
        let b = color(1)
        ZStack {
            Circle().fill(RadialGradient(colors: [a, b], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 4, endRadius: 80))
            Circle()
                .fill(LinearGradient(colors: [Color.clear, b.opacity(0.55), Color.clear, a.opacity(0.4), Color.clear],
                                     startPoint: .top, endPoint: .bottom))
                .blendMode(.overlay)
            Circle().fill(RadialGradient(colors: [Color.clear, Color.black.opacity(0.45)], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 30, endRadius: 85))
        }
        .clipShape(Circle())
        .shadow(color: a.opacity(0.6), radius: 18)
    }

    private func color(_ i: Int) -> Color {
        let hex = i < colors.count ? colors[i] : (colors.first ?? "#888888")
        let c = BlockRegistry.parseHex(hex)
        return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }
}

/// Shown while the starship is in flight.
struct TravelView: View {
    let text: String

    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.02, blue: 0.09).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "sparkles")
                    .font(.gameIcon(54))
                    .foregroundStyle(Color(red: 0.37, green: 0.94, blue: 1.0))
                Text(text)
                    .font(.game(38).weight(.heavy))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Title screen

/// The splash and title: Wolfie World with its wolf face beside the chrome title,
/// while the live world circles slowly behind.
struct TitleView: View {
    let game: Game

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let wide = w > h * 1.15
            let planet = wide ? min(h * 0.86, w * 0.44) : min(w * 0.7, h * 0.42)

            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.03, blue: 0.16).opacity(0.9), Color(red: 0.05, green: 0.03, blue: 0.16).opacity(0.35), Color(red: 0.05, green: 0.03, blue: 0.16).opacity(0.92)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                Twinkles()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                if wide {
                    HStack(spacing: w * 0.02) {
                        PlanetEmblem()
                            .frame(width: planet, height: planet)
                        titleAndMenu(width: min(w * 0.5, 760))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 8) {
                        PlanetEmblem()
                            .frame(width: planet, height: planet)
                        titleAndMenu(width: min(w * 0.9, 640))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func titleAndMenu(width: CGFloat) -> some View {
        VStack(spacing: 22) {
            GameTitle()
                .frame(width: width)
            VStack(spacing: 12) {
                ForEach(Array(game.menuItems.enumerated()), id: \.offset) { index, item in
                    MenuRow(game: game, item: item, selected: index == game.menuIndex, big: true)
                }
            }
            .frame(maxWidth: UIMetrics.points(400))
            Text(game.keyboardMode ? "Arrows to choose · Return to go" : "Stick to choose · A to go")
                .font(.game(13).weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.6))
                .oneLine()
            Text(Game.versionText)
                .font(.game(12).weight(.medium).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0.45))
                .oneLine()
        }
        .animation(.spring(duration: 0.2), value: game.menuIndex)
    }
}

/// Little stars that blink over the title.
struct Twinkles: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<70 {
                    let fx = (sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let fy = (sin(Double(i) * 78.233) * 12345.6789).truncatingRemainder(dividingBy: 1)
                    let x = abs(fx) * size.width
                    let y = abs(fy) * size.height * 0.55
                    let blink = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * (1.2 + Double(i % 5) * 0.4) + Double(i)))
                    let r = 1.2 + Double(i % 3) * 0.7
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(Color.white.opacity(blink)))
                }
            }
        }
    }
}

// MARK: - Pause and settings

struct MenuPanel: View {
    let game: Game

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.03, blue: 0.12).opacity(0.78)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text(title)
                    .font(.game(40).weight(.heavy))
                    .foregroundStyle(.white)
                if game.screen == .paused {
                    Text([game.planet.name, game.togetherSummary].compactMap { $0 }.joined(separator: " · "))
                        .font(.game(20).weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .oneLine()
                }
                if game.screen == .friends {
                    Text(game.message.isEmpty ? "Everyone needs to be on the same Wi-Fi" : game.message)
                        .font(.game(18).weight(.semibold))
                        .foregroundStyle(game.message.isEmpty ? Color.white.opacity(0.7) : Color(red: 1.0, green: 0.71, blue: 0.28))
                        .oneLine()
                }
                VStack(spacing: 12) {
                    ForEach(Array(game.menuItems.enumerated()), id: \.offset) { index, item in
                        MenuRow(game: game, item: item, selected: index == game.menuIndex, big: false)
                    }
                }
                .frame(maxWidth: UIMetrics.points(520))
                Text(hint)
                    .font(.game(13).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .oneLine()
                if game.screen == .paused {
                    Text(Game.versionText)
                        .font(.game(12).weight(.medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.45))
                        .oneLine()
                }
            }
            .padding(28)
        }
        .animation(.spring(duration: 0.2), value: game.menuIndex)
    }

    private var title: String {
        switch game.screen {
        case .settings: return "Settings"
        case .friends: return "Play together"
        default: return "Paused"
        }
    }

    private var hint: String {
        if game.screen == .settings || game.screen == .friends {
            return game.keyboardMode ? "Arrows to choose and change · Esc to go back" : "Stick to choose and change · B to go back"
        }
        return game.keyboardMode ? "Arrows to choose · Return to pick · Esc to keep playing" : "Stick to choose · A to pick · B to keep playing"
    }
}

/// One choice in a menu. Settings show their value on the right.
struct MenuRow: View {
    let game: Game
    let item: Game.MenuItem
    let selected: Bool
    let big: Bool
    private let amber = Color(red: 1.0, green: 0.71, blue: 0.28)

    var body: some View {
        let words = game.label(for: item)
        HStack(spacing: 12) {
            Text(words.title)
                .font(.game(big ? 28 : 20).weight(.bold))
            Spacer(minLength: 8)
            if let value = words.value {
                Text(value)
                    .font(.game(big ? 20 : 17).weight(.semibold))
                    .foregroundStyle(selected ? amber : Color.white.opacity(0.65))
            }
        }
        .foregroundStyle(.white)
        .oneLine()
        .padding(.horizontal, UIMetrics.points(22))
        .padding(.vertical, UIMetrics.points(big ? 16 : 13))
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(selected ? 0.16 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? amber : Color.white.opacity(0.14), lineWidth: selected ? 3 : 1))
        .scaleEffect(selected ? 1.03 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture { game.tapMenu(item) }
    }
}

// MARK: - Controls

/// Every control, for the keyboard and mouse and for a game controller.
struct ControlsPanel: View {
    let game: Game

    struct Row: Identifiable {
        let id = UUID()
        let action: String
        let keys: [String]
        let keysNote: String?
        let pad: [String]
    }

    static let rows: [Row] = [
        Row(action: "Walk", keys: ["W", "A", "S", "D"], keysNote: "or arrow keys", pad: ["Left stick"]),
        Row(action: "Look around", keys: ["Mouse"], keysNote: "click the game first", pad: ["Right stick"]),
        Row(action: "Jump", keys: ["Space"], keysNote: nil, pad: ["A"]),
        Row(action: "Start or stop flying", keys: ["Space", "Space"], keysNote: "double-tap", pad: ["A", "A"]),
        Row(action: "Fly up, fly down", keys: ["Space", "Shift"], keysNote: "or C to go down", pad: ["A", "B"]),
        Row(action: "Break a block, fire the laser", keys: ["Left click"], keysNote: "hold to keep going", pad: ["RT"]),
        Row(action: "Place a block, pet a critter", keys: ["Right click"], keysNote: nil, pad: ["LT"]),
        Row(action: "Pick from the hotbar", keys: ["1", "–", "6"], keysNote: "or Q and E", pad: ["LB", "RB"]),
        Row(action: "Get in or out of the rover or starship", keys: ["F"], keysNote: "or Y", pad: ["Y"]),
        Row(action: "Starship: star map · Rover: honk", keys: ["M", "H"], keysNote: nil, pad: ["X"]),
        Row(action: "Pause, settings, controls", keys: ["Esc"], keysNote: "or P", pad: ["Menu ≡"]),
        Row(action: "Let go of the mouse", keys: ["Esc"], keysNote: nil, pad: []),
        Row(action: "In menus: choose, pick, go back", keys: ["↑", "↓", "Return", "Esc"], keysNote: nil, pad: ["Stick", "A", "B"])
    ]

    #if os(tvOS)
    private let showKeyboard = false
    #else
    private let showKeyboard = true
    #endif

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.03, blue: 0.12).opacity(0.86)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Controls")
                    .font(.game(40).weight(.heavy))
                    .foregroundStyle(.white)

                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 12) {
                        GridRow {
                            Text("")
                            if showKeyboard { header("Keyboard and mouse") }
                            header("Controller")
                        }
                        ForEach(ControlsPanel.rows) { row in
                            GridRow {
                                Text(row.action)
                                    .font(.game(17))
                                    .foregroundStyle(.white)
                                    .fixedSize(horizontal: false, vertical: true)
                                if showKeyboard {
                                    HStack(spacing: 6) {
                                        ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in
                                            if key == "–" {
                                                Text("to").foregroundStyle(Color.white.opacity(0.6))
                                            } else {
                                                KeyCap(text: key)
                                            }
                                        }
                                        if let note = row.keysNote {
                                            Text(note)
                                                .font(.game(15))
                                                .foregroundStyle(Color.white.opacity(0.65))
                                        }
                                    }
                                }
                                HStack(spacing: 6) {
                                    if row.pad.isEmpty {
                                        Text("—").foregroundStyle(Color.white.opacity(0.4))
                                    }
                                    ForEach(Array(row.pad.enumerated()), id: \.offset) { _, button in
                                        KeyCap(text: button, round: true)
                                    }
                                }
                            }
                            Divider().overlay(Color.white.opacity(0.08)).gridCellUnsizedAxes(.horizontal)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(maxWidth: UIMetrics.points(940))

                MenuRow(game: game, item: .back, selected: true, big: false)
                    .frame(maxWidth: UIMetrics.points(320))
                Text(game.keyboardMode ? "Esc or Return to go back" : "B or A to go back")
                    .font(.game(13).weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .oneLine()
            }
            .padding(28)
        }
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.game(12).weight(.heavy))
            .tracking(1.5)
            .foregroundStyle(Color(red: 1.0, green: 0.71, blue: 0.28))
    }
}

/// A keyboard key, or (round) a controller button.
struct KeyCap: View {
    let text: String
    var round = false

    var body: some View {
        Text(text)
            .font(.game(15).weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(minWidth: 30)
            .background(
                RoundedRectangle(cornerRadius: round ? 14 : 7)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: round ? 14 : 7)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .overlay(alignment: .bottom) {
                if !round {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 3)
                        .padding(.horizontal, 3)
                        .offset(y: 3)
                }
            }
    }
}
