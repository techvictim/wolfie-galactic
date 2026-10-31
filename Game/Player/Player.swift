import Foundation
import simd

struct RayHit {
    /// The block being looked at.
    let block: SIMD3<Int>
    /// The empty cell in front of it, where a new block goes.
    let previous: SIMD3<Int>
}

/// Walks a ray through the block grid (Amanatides & Woo).
func raycast(world: World, origin: SIMD3<Float>, direction: SIMD3<Float>, maxDistance: Float) -> RayHit? {
    var cell = SIMD3<Int>(Int(floor(origin.x)), Int(floor(origin.y)), Int(floor(origin.z)))
    let step = SIMD3<Int>(direction.x > 0 ? 1 : -1, direction.y > 0 ? 1 : -1, direction.z > 0 ? 1 : -1)

    func firstBoundary(_ o: Float, _ d: Float, _ c: Int) -> Float {
        if d > 0 { return (Float(c) + 1 - o) / d }
        if d < 0 { return (o - Float(c)) / -d }
        return .infinity
    }
    func delta(_ d: Float) -> Float {
        d != 0 ? abs(1 / d) : .infinity
    }

    var tMax = SIMD3<Float>(
        firstBoundary(origin.x, direction.x, cell.x),
        firstBoundary(origin.y, direction.y, cell.y),
        firstBoundary(origin.z, direction.z, cell.z)
    )
    let tDelta = SIMD3<Float>(delta(direction.x), delta(direction.y), delta(direction.z))
    var previous = cell
    var t: Float = 0

    while t <= maxDistance {
        if world.block(cell) != B.air {
            return RayHit(block: cell, previous: previous)
        }
        previous = cell
        if tMax.x < tMax.y && tMax.x < tMax.z {
            cell.x += step.x
            t = tMax.x
            tMax.x += tDelta.x
        } else if tMax.y < tMax.z {
            cell.y += step.y
            t = tMax.y
            tMax.y += tDelta.y
        } else {
            cell.z += step.z
            t = tMax.z
            tMax.z += tDelta.z
        }
    }
    return nil
}

/// The local player: a 0.6 x 1.8 m box that walks, jumps and bumps into blocks.
struct Player {
    static let halfWidth: Float = 0.3
    static let height: Float = 1.8
    static let eyeHeight: Float = 1.62
    static let walkSpeed: Float = 4.5
    static let jumpSpeed: Float = 8.6
    static let reach: Float = 6
    static let laserRange: Float = 32
    static let flySpeed: Float = 11
    static let flyClimb: Float = 8

    /// Feet position.
    var position: SIMD3<Float>
    var velocity = SIMD3<Float>(repeating: 0)
    var yaw: Float = 0
    var pitch: Float = -0.2
    var onGround = false
    /// Double-tap jump to fly; touching the ground while flying down lands you.
    var flying = false
    /// A shove (from a grumpy critter) that fades over a moment.
    var push = SIMD3<Float>(repeating: 0)

    init(position: SIMD3<Float>) {
        self.position = position
    }

    var eye: SIMD3<Float> {
        position + SIMD3<Float>(0, Player.eyeHeight, 0)
    }

    var lookDirection: SIMD3<Float> {
        SIMD3<Float>(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    var orientation: simd_quatf {
        simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: pitch, axis: SIMD3<Float>(1, 0, 0))
    }

    func overlaps(_ p: SIMD3<Float>, world: World) -> Bool {
        let minX = Int(floor(p.x - Player.halfWidth))
        let maxX = Int(floor(p.x + Player.halfWidth - 0.001))
        let minY = Int(floor(p.y))
        let maxY = Int(floor(p.y + Player.height - 0.001))
        let minZ = Int(floor(p.z - Player.halfWidth))
        let maxZ = Int(floor(p.z + Player.halfWidth - 0.001))
        for x in minX...maxX {
            for y in minY...maxY {
                for z in minZ...maxZ where world.isSolidForPhysics(x, y, z) {
                    return true
                }
            }
        }
        return false
    }

    /// True if a block at this cell would sit inside the player.
    func occupies(_ cell: SIMD3<Int>) -> Bool {
        let p = position
        return Float(cell.x) < p.x + Player.halfWidth && Float(cell.x + 1) > p.x - Player.halfWidth
            && Float(cell.y) < p.y + Player.height && Float(cell.y + 1) > p.y
            && Float(cell.z) < p.z + Player.halfWidth && Float(cell.z + 1) > p.z - Player.halfWidth
    }

    /// Get knocked back: sideways and a little up.
    mutating func knock(_ v: SIMD3<Float>) {
        push = SIMD3<Float>(v.x, 0, v.z)
        if !flying { velocity.y = max(velocity.y, v.y) }
    }

    mutating func step(dt: Float, move: SIMD2<Float>, jump: Bool, descend: Bool = false, gravity: Float, world: World) {
        let forward = SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
        let right = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        var wish = forward * move.y + right * move.x
        let length = simd_length(wish)
        if length > 1 { wish /= length }
        if flying {
            velocity.x = wish.x * Player.flySpeed + push.x
            velocity.z = wish.z * Player.flySpeed + push.z
            velocity.y = ((jump ? 1 : 0) - (descend ? 1 : 0)) * Player.flyClimb
        } else {
            velocity.x = wish.x * Player.walkSpeed + push.x
            velocity.z = wish.z * Player.walkSpeed + push.z
            if jump && onGround { velocity.y = Player.jumpSpeed }
            velocity.y = max(velocity.y - gravity * dt, -30)
        }

        push *= max(0, 1 - dt * 5)

        // Small sub-steps so fast falls can't pass through a block.
        let largest = max(abs(velocity.x), abs(velocity.y), abs(velocity.z)) * dt
        let steps = max(1, Int(ceil(largest / 0.35)))
        let h = dt / Float(steps)
        onGround = false

        for _ in 0..<steps {
            var p = position
            p.x += velocity.x * h
            if overlaps(p, world: world) { p.x = position.x }
            p.z += velocity.z * h
            if overlaps(p, world: world) { p.z = position.z }

            let before = p.y
            p.y += velocity.y * h
            if overlaps(p, world: world) {
                if velocity.y < 0 {
                    var snapped = p
                    snapped.y = floor(p.y) + 1
                    p.y = (snapped.y <= before + 0.001 && !overlaps(snapped, world: world)) ? snapped.y : before
                    onGround = true
                    flying = false
                } else {
                    p.y = before
                }
                velocity.y = 0
            }
            position = p
        }
    }
}
