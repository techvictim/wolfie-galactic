import Foundation

/// The names of buttons for on-screen hints: PlayStation symbols with a DualSense (✕ ○ △ □, L2, R2),
/// Xbox letters with an Xbox controller. Keyboard names are written where they're used.
enum Btn {
    static var ps: Bool { InputController.playStation }

    /// Jump, fly up, pick in menus.
    static var cross: String { ps ? "✕" : "A" }
    /// Get out, fly down, back in menus.
    static var circle: String { ps ? "○" : "B" }
    /// Inventory (the backpack).
    static var triangle: String { ps ? "△" : "Y" }
    /// Crafting; the star map and horn in vehicles.
    static var square: String { ps ? "□" : "X" }
    /// Break, fire.
    static var fire: String { ps ? "R2" : "RT" }
    /// Place, use, get in, pet.
    static var use: String { ps ? "L2" : "LT" }
    static var bumpers: String { ps ? "L1  R1" : "LB  RB" }
    static var sprint: String { ps ? "L3" : "LS" }
    static var view: String { "D-pad ↑" }
    static var map: String { ps ? "Touchpad" : "D-pad ↓" }
    static var pause: String { ps ? "Options" : "≡" }
    static var help: String { ps ? "Create" : "View" }
}
