import Foundation
import simd

/// The Wolfie Military crew: picking who you play as, seeing them from behind, and their voices.
extension Game {
    var crewMember: CrewMember { Crew.member(GameSettings.shared.crew) }

    // MARK: Your character

    /// Stand your character where you are and move their arms and legs.
    func updateMe(dt: Float) {
        let show = GameSettings.shared.viewBehind && !cameraCrowded
        me.root.isEnabled = show
        guard show else {
            lastMePosition = nil
            return
        }
        let position = player.position
        var speed: Float = 0
        if let last = lastMePosition, dt > 0 {
            let step = position - last
            speed = simd_length(SIMD2<Float>(step.x, step.z)) / dt
        }
        lastMePosition = position
        me.root.position = position
        me.root.orientation = simd_quatf(angle: player.yaw, axis: SIMD3<Float>(0, 1, 0))
        let jetting = player.flying || critterClock - jumpPadClock < 1.2
        me.animate(dt: dt, speed: speed, pitch: player.pitch, flying: jetting, aiming: laserSelected)
    }

    // MARK: Picking a character

    func openCrewPicker() {
        menuReturn = screen
        crewIndex = Crew.all.firstIndex { $0.id == GameSettings.shared.crew } ?? 0
        screen = .crew
    }

    func closeCrewPicker() {
        screen = menuReturn
        menuIndex = menuItems.firstIndex(of: .crew) ?? 0
    }

    static let crewColumns = 4

    func updateCrewPicker(_ frame: InputFrame) {
        if frame.cancel || frame.pause {
            closeCrewPicker()
            return
        }
        let count = Crew.all.count
        var index = crewIndex
        if frame.menuStep != 0 { index = (index + frame.menuStep + count) % count }
        if frame.menuMove != 0 { index = max(0, min(count - 1, index + frame.menuMove * Game.crewColumns)) }
        if index != crewIndex {
            crewIndex = index
            Sound.shared.play("menu-move")
        }
        if frame.confirm { pickCrew(Crew.all[crewIndex]) }
    }

    /// Tap a character once to look, twice to pick.
    func tapCrew(_ index: Int) {
        guard Crew.all.indices.contains(index) else { return }
        if index == crewIndex {
            pickCrew(Crew.all[index])
        } else {
            crewIndex = index
            Sound.shared.play("menu-move")
        }
    }

    func pickCrew(_ member: CrewMember) {
        let settings = GameSettings.shared
        settings.crew = member.id
        Sound.shared.play("menu-select", volume: 0.7)
        Voices.shared.say("pick", as: member.id, cooldown: 0, interrupt: true)
        // Swap the figure.
        let wasShown = me.root.isEnabled
        me.root.removeFromParent()
        me = CrewRig(member.id)
        me.root.isEnabled = wasShown
        root.addChild(me.root)
        lastMePosition = nil
        show("You're \(member.name)!")
        closeCrewPicker()
    }

    // MARK: Things the crew say

    /// A block got blasted: lots in a row gets a "Timber!", now and then a laugh.
    func noteBlockBlasted() {
        let now = critterClock
        recentBlasts.append(now)
        recentBlasts.removeAll { now - $0 > 3 }
        if recentBlasts.count >= 10 {
            recentBlasts.removeAll()
            Voices.shared.say("down", cooldown: 14)
        } else {
            Voices.shared.say("laugh", chance: 0.03, cooldown: 12)
        }
    }

    /// A vehicle bolt went boom.
    func noteBigBlast() {
        Voices.shared.say("blast", chance: 0.3, cooldown: 20)
    }
}
