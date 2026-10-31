import Foundation
import GameController
import simd
#if os(macOS)
import AppKit
#endif

/// Everything the game needs from the player's hands for one frame.
struct InputFrame {
    /// Walk direction: x = strafe right, y = forward. Range -1...1.
    var move = SIMD2<Float>(repeating: 0)
    /// Look change this frame, in radians: x = yaw, y = pitch (before settings are applied).
    var look = SIMD2<Float>(repeating: 0)
    var jump = false
    /// Jump pressed this frame (for double-tap to fly).
    var jumpPressed = false
    /// Fly down: B on a controller, Shift or C on a keyboard.
    var descend = false
    var breakHeld = false
    var placeHeld = false
    var hotbarStep = 0
    var hotbarSelect: Int?
    /// Y on a controller; Y or F on a keyboard: board the starship.
    var openMap = false
    /// X on a controller; M or H on a keyboard, once per press: the starship's star map, the rover's horn.
    var action = false
    /// The controls card: Create/View/Share on a controller, ? on a keyboard. Once per press.
    var help = false
    /// A, Return or Space, once per press.
    var confirm = false
    /// B or Esc, once per press.
    var cancel = false
    /// Menu button, Esc or P, once per press.
    var pause = false
    /// Left/right once per push, for menus and values.
    var menuStep = 0
    /// Up/down once per push, for menus. Down is +1.
    var menuMove = 0
}

/// The keys the game uses, on any keyboard.
enum Key: CaseIterable {
    case w, a, s, d, q, e, f, y, p, c, m, h, slash
    case space, enter, escape
    case up, down, left, right
    case one, two, three, four, five, six
}

/// Reads game controllers, the on-screen controller (iPad), and keyboard + mouse.
///
/// Controller: left stick walk · right stick look · A jump · right trigger break/fire ·
/// left trigger place · bumpers change slot · Y fly the starship · Menu pause.
/// Keyboard: WASD walk · mouse look (click to capture) · Space jump · left click break/fire ·
/// right click place · 1–6 or Q/E change slot · Y or F fly the starship · Esc or P pause.
@MainActor
final class InputController {
    static let stickLookSpeed: Float = 2.6
    static let mouseLookSpeed: Float = 0.0025

    private var previous: [String: Bool] = [:]
    private var mouseDelta = SIMD2<Float>(repeating: 0)
    private var started = false
    private var observers: [NSObjectProtocol] = []
    private(set) var pointerCaptured = false
    private var waitForMouseRelease = false
    /// True after a key press, false after controller input: picks which button names to show.
    #if os(macOS)
    private(set) var usingKeyboard = true
    #else
    private(set) var usingKeyboard = false
    #endif
    /// Mouse look only while playing.
    var mouseLookEnabled = false

    #if os(iOS)
    private var virtualController: GCVirtualController?
    #endif

    #if os(macOS)
    /// Keys currently held, read straight from AppKit so every press registers.
    private var macKeysDown = Set<UInt16>()
    private var macShiftDown = false
    private var keyMonitor: Any?
    private static let macKeyCodes: [Key: UInt16] = [
        .w: 13, .a: 0, .s: 1, .d: 2, .q: 12, .e: 14, .f: 3, .y: 16, .p: 35, .c: 8, .m: 46, .h: 4, .slash: 44,
        .space: 49, .enter: 36, .escape: 53,
        .up: 126, .down: 125, .left: 123, .right: 124,
        .one: 18, .two: 19, .three: 20, .four: 21, .five: 23, .six: 22
    ]
    #endif

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controllersChanged() }
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.controllersChanged() }
        })
        observers.append(center.addObserver(forName: .GCMouseDidConnect, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                if let mouse = note.object as? GCMouse { self?.attach(mouse) }
            }
        })
        for mouse in GCMouse.mice() { attach(mouse) }

        #if os(macOS)
        // Handle the game's keys ourselves; this also stops the "beep" for unhandled keys.
        // Keys pressed with ⌘ pass through, so ⌘Q and other menu shortcuts still work.
        let handled = Set(InputController.macKeyCodes.values)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            if event.type == .flagsChanged {
                let shift = event.modifierFlags.contains(.shift)
                MainActor.assumeIsolated { self?.macShiftDown = shift }
                return event
            }
            if event.modifierFlags.contains(.command) { return event }
            guard handled.contains(event.keyCode) else { return event }
            MainActor.assumeIsolated {
                if event.type == .keyDown {
                    self?.macKeysDown.insert(event.keyCode)
                } else {
                    self?.macKeysDown.remove(event.keyCode)
                }
            }
            return nil
        }
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.macKeysDown.removeAll()
                self?.macShiftDown = false
                self?.releasePointer()
            }
        })
        #endif

        controllersChanged()
    }

    private func attach(_ mouse: GCMouse) {
        mouse.mouseInput?.mouseMovedHandler = { [weak self] _, dx, dy in
            MainActor.assumeIsolated {
                self?.mouseDelta += SIMD2<Float>(dx, dy)
            }
        }
    }

    private func controllersChanged() {
        #if os(iOS)
        // Show on-screen sticks and buttons only when no real controller is connected.
        let hasPhysical = GCController.controllers().contains { controller in
            controller !== virtualController?.controller && controller.extendedGamepad != nil
        }
        if hasPhysical {
            virtualController?.disconnect()
        } else {
            if virtualController == nil {
                let configuration = GCVirtualController.Configuration()
                configuration.elements = [
                    GCInputLeftThumbstick, GCInputRightThumbstick,
                    GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY,
                    GCInputRightTrigger, GCInputLeftTrigger,
                    GCInputLeftShoulder, GCInputRightShoulder
                ]
                virtualController = GCVirtualController(configuration: configuration)
            }
            virtualController?.connect(replyHandler: nil)
        }
        #endif
    }

    /// True once per press.
    private func pressed(_ key: String, _ isDown: Bool) -> Bool {
        let was = previous[key] ?? false
        previous[key] = isDown
        return isDown && !was
    }

    private func deadzone(_ v: Float) -> Float {
        abs(v) < 0.15 ? 0 : v
    }

    private func isDown(_ key: Key) -> Bool {
        #if os(macOS)
        if let code = InputController.macKeyCodes[key], macKeysDown.contains(code) { return true }
        #endif
        guard let keyboard = GCKeyboard.coalesced?.keyboardInput else { return false }
        let code: GCKeyCode
        switch key {
        case .w: code = .keyW
        case .a: code = .keyA
        case .s: code = .keyS
        case .d: code = .keyD
        case .q: code = .keyQ
        case .e: code = .keyE
        case .f: code = .keyF
        case .y: code = .keyY
        case .p: code = .keyP
        case .c: code = .keyC
        case .m: code = .keyM
        case .h: code = .keyH
        case .slash: code = .slash
        case .space: code = .spacebar
        case .enter: code = .returnOrEnter
        case .escape: code = .escape
        case .up: code = .upArrow
        case .down: code = .downArrow
        case .left: code = .leftArrow
        case .right: code = .rightArrow
        case .one: code = .one
        case .two: code = .two
        case .three: code = .three
        case .four: code = .four
        case .five: code = .five
        case .six: code = .six
        }
        return keyboard.button(forKeyCode: code)?.isPressed ?? false
    }

    func poll(dt: Float) -> InputFrame {
        var frame = InputFrame()

        // Game controllers (including the iPad's on-screen one).
        for (i, controller) in GCController.controllers().enumerated() {
            guard let pad = controller.extendedGamepad else {
                // The Siri Remote: enough to use the menus and pause.
                if let remote = controller.microGamepad {
                    let id = "remote\(i)"
                    remote.reportsAbsoluteDpadValues = false
                    let x = remote.dpad.xAxis.value
                    let y = remote.dpad.yAxis.value
                    if pressed(id + ".right", x > 0.5) { frame.menuStep += 1 }
                    if pressed(id + ".left", x < -0.5) { frame.menuStep -= 1 }
                    if pressed(id + ".down", y < -0.5) { frame.menuMove += 1 }
                    if pressed(id + ".up", y > 0.5) { frame.menuMove -= 1 }
                    if pressed(id + ".select", remote.buttonA.isPressed) { frame.confirm = true }
                    if pressed(id + ".menu", remote.buttonMenu.isPressed) {
                        frame.cancel = true
                        frame.pause = true
                    }
                }
                continue
            }
            let lx = deadzone(pad.leftThumbstick.xAxis.value)
            let ly = deadzone(pad.leftThumbstick.yAxis.value)
            let rx = deadzone(pad.rightThumbstick.xAxis.value)
            let ry = deadzone(pad.rightThumbstick.yAxis.value)
            if abs(lx) > abs(frame.move.x) { frame.move.x = lx }
            if abs(ly) > abs(frame.move.y) { frame.move.y = ly }
            // Squared response: gentle near the centre for precise aiming.
            frame.look.x -= rx * abs(rx) * InputController.stickLookSpeed * dt
            frame.look.y += ry * abs(ry) * InputController.stickLookSpeed * 0.75 * dt
            frame.jump = frame.jump || pad.buttonA.isPressed
            frame.descend = frame.descend || pad.buttonB.isPressed
            frame.breakHeld = frame.breakHeld || pad.rightTrigger.isPressed
            frame.placeHeld = frame.placeHeld || pad.leftTrigger.isPressed
            let id = "pad\(i)"
            if pressed(id + ".rb", pad.rightShoulder.isPressed) { frame.hotbarStep += 1 }
            if pressed(id + ".lb", pad.leftShoulder.isPressed) { frame.hotbarStep -= 1 }
            if pressed(id + ".y", pad.buttonY.isPressed) { frame.openMap = true }
            if pressed(id + ".x", pad.buttonX.isPressed) { frame.action = true }
            if pressed(id + ".options", pad.buttonOptions?.isPressed ?? false) { frame.help = true }
            if pressed(id + ".a", pad.buttonA.isPressed) {
                frame.confirm = true
                frame.jumpPressed = true
            }
            if pressed(id + ".b", pad.buttonB.isPressed) { frame.cancel = true }
            // Options / Menu (≡) pauses on every device.
            if pressed(id + ".menu", pad.buttonMenu.isPressed) { frame.pause = true }
            if pressed(id + ".right", lx > 0.6 || pad.dpad.right.isPressed) { frame.menuStep += 1 }
            if pressed(id + ".left", lx < -0.6 || pad.dpad.left.isPressed) { frame.menuStep -= 1 }
            if pressed(id + ".down", ly < -0.6 || pad.dpad.down.isPressed) { frame.menuMove += 1 }
            if pressed(id + ".up", ly > 0.6 || pad.dpad.up.isPressed) { frame.menuMove -= 1 }

            let active = lx != 0 || ly != 0 || rx != 0 || ry != 0 || pad.buttonA.isPressed
                || pad.rightTrigger.isPressed || pad.leftTrigger.isPressed
            if active { usingKeyboard = false }
        }

        // Keyboard.
        var kx: Float = 0
        var kz: Float = 0
        if isDown(.w) || isDown(.up) { kz += 1 }
        if isDown(.s) || isDown(.down) { kz -= 1 }
        if isDown(.d) || isDown(.right) { kx += 1 }
        if isDown(.a) || isDown(.left) { kx -= 1 }
        if kx != 0 || kz != 0 {
            frame.move = SIMD2<Float>(kx, kz)
            usingKeyboard = true
        }
        if isDown(.space) {
            frame.jump = true
            usingKeyboard = true
        }
        if pressed("key.jump", isDown(.space)) { frame.jumpPressed = true }
        var shift = false
        #if os(macOS)
        shift = macShiftDown
        #endif
        if let keyboard = GCKeyboard.coalesced?.keyboardInput {
            shift = shift || (keyboard.button(forKeyCode: .leftShift)?.isPressed ?? false)
                || (keyboard.button(forKeyCode: .rightShift)?.isPressed ?? false)
        }
        if shift || isDown(.c) { frame.descend = true }
        let slotKeys: [Key] = [.one, .two, .three, .four, .five, .six]
        for (i, key) in slotKeys.enumerated() where pressed("key.slot\(i)", isDown(key)) {
            frame.hotbarSelect = i
            usingKeyboard = true
        }
        if pressed("key.q", isDown(.q)) { frame.hotbarStep -= 1 }
        if pressed("key.e", isDown(.e)) { frame.hotbarStep += 1 }
        if pressed("key.fly", isDown(.f) || isDown(.y)) {
            frame.openMap = true
            usingKeyboard = true
        }
        if pressed("key.help", isDown(.slash)) {
            frame.help = true
            usingKeyboard = true
        }
        if pressed("key.action", isDown(.m) || isDown(.h)) {
            frame.action = true
            usingKeyboard = true
        }
        if pressed("key.confirm", isDown(.enter) || isDown(.space)) { frame.confirm = true }
        if pressed("key.esc", isDown(.escape)) {
            frame.cancel = true
            frame.pause = true
            usingKeyboard = true
        }
        if pressed("key.p", isDown(.p)) { frame.pause = true }
        if pressed("key.right", isDown(.right) || isDown(.d)) { frame.menuStep += 1 }
        if pressed("key.left", isDown(.left) || isDown(.a)) { frame.menuStep -= 1 }
        if pressed("key.down", isDown(.down) || isDown(.s)) { frame.menuMove += 1 }
        if pressed("key.up", isDown(.up) || isDown(.w)) { frame.menuMove -= 1 }

        // Mouse (Mac): click once to capture the pointer, then it steers the camera.
        #if os(macOS)
        if !mouseLookEnabled { releasePointer() }
        if let mouse = GCMouse.current?.mouseInput {
            let left = mouse.leftButton.isPressed
            let right = mouse.rightButton?.isPressed ?? false
            if pointerCaptured {
                frame.look.x -= mouseDelta.x * InputController.mouseLookSpeed
                frame.look.y += mouseDelta.y * InputController.mouseLookSpeed
                if waitForMouseRelease {
                    if !left { waitForMouseRelease = false }
                } else {
                    frame.breakHeld = frame.breakHeld || left
                }
                frame.placeHeld = frame.placeHeld || right
                if left || right { usingKeyboard = true }
            } else if mouseLookEnabled && pressed("mouse.capture", left) {
                capturePointer()
            }
        }
        #endif
        mouseDelta = .zero
        return frame
    }

    #if os(macOS)
    func capturePointer() {
        guard !pointerCaptured else { return }
        pointerCaptured = true
        waitForMouseRelease = true
        NSCursor.hide()
        CGAssociateMouseAndMouseCursorPosition(0)
    }

    func releasePointer() {
        guard pointerCaptured else { return }
        pointerCaptured = false
        NSCursor.unhide()
        CGAssociateMouseAndMouseCursorPosition(1)
    }
    #endif
}
