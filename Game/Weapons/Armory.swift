import Foundation
import RealityKit
import simd

/// Everything the weapons have going on: things in flight, charges stuck to walls, mines,
/// air strikes on their way, mushroom clouds and the black hole.
@MainActor
final class Armory {
    let root = Entity()

    /// Something fired, thrown, dropped or stuck on.
    struct Shot {
        let entity: Entity
        let light: ModelEntity?
        let look: String
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var gravity: Float
        var radius: Float
        var age: Float = 0
        /// Seconds until it blows; 0 means it blows when it hits something.
        var fuse: Float = 0
        var bounce = false
        var pierceLeft = 0
        var drillLeft = 0
        var drilling = false
        var sticky = false
        var stuck = false
        var remote = false
        var mine = false
        var armed: Float = 0
        /// Bursts into this many little bombs.
        var bomblets = 0
        /// Air strikes fly through anything until they're close to where they're going.
        var target: SIMD3<Float>?
        /// Drones steer toward their target.
        var homing = false
        var trail = 0
        var trailTimer: Float = 0
        var whistled = false
        var nuke = false
    }

    /// A ship flying over on an air strike.
    struct Flyer {
        let entity: Entity
        let turn: simd_quatf
        var start: SIMD3<Float>
        var end: SIMD3<Float>
        var duration: Float
        var age: Float = 0
        /// Circles the point instead of flying across.
        var circle: SIMD3<Float>?
    }

    /// The black hole while it's open.
    struct Hole {
        let visual: BlackHoleVisual
        let center: SIMD3<Float>
        var cells: [SIMD3<Int>]
        var next = 0
        var age: Float = 0
        let duration: Float
        let radius: Float
        var eaten = 0
        var closed = false
        var critterTimer: Float = 0
    }

    var shots: [Shot] = []
    var flyers: [Flyer] = []
    var clouds: [MushroomCloud] = []
    var hole: Hole?
    /// Things to do a little later: bombs falling one after another, a ready message.
    var pending: [(time: Float, run: () -> Void)] = []

    var clock: Float = 0
    var cooldown: Float = 0
    var lastTrigger = false
    var lastPlace = false
    var flameTimer: Float = 0
    var flameSpray: Float = 0
    var flaming = false
    var holeReadyAt: Float = 0
    var holeWaiting = false
    var holeRecharge: Float = 30
    /// Camera wobble from big booms.
    var shake: Float = 0
    var zoomed = false

    static let maxShots = 90

    func later(_ seconds: Float, _ run: @escaping () -> Void) {
        pending.append((clock + seconds, run))
    }

    func clear() {
        for s in shots { s.entity.removeFromParent() }
        shots.removeAll()
        for f in flyers { f.entity.removeFromParent() }
        flyers.removeAll()
        for c in clouds { c.root.removeFromParent() }
        clouds.removeAll()
        hole?.visual.root.removeFromParent()
        hole = nil
        pending.removeAll()
        flaming = false
    }
}
