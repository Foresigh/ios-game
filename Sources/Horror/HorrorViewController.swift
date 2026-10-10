import UIKit
import SceneKit

/// THE HOUSE — a first-person horror game. Find three keys in a dark house
/// and get out through the front door before the creature catches you.
///
/// Left side of the screen: drag to walk (push all the way to run, which it
/// can hear). Right side: drag to look around.
final class HorrorViewController: UIViewController, SCNSceneRendererDelegate {

    private enum Phase { case intro, playing, caught, escaped }

    private let map = HorrorMap(HorrorMap.house)
    private let audio = HorrorAudio()
    private let scnView = SCNView()
    private let scene = SCNScene()
    private let player = SCNNode()          // turns left/right
    private let camera = SCNNode()          // tilts up/down
    private let flashlight = SCNLight()
    private let creature = HorrorCreature()
    private var keyNodes: [GridPoint: SCNNode] = [:]
    private var batteryNodes: [GridPoint: SCNNode] = [:]
    private var doorPoint = SCNVector3Zero

    // Game state (advanced on SceneKit's render thread).
    private var phase = Phase.intro
    private var yaw: Float = -.pi / 2
    private var pitch: Float = 0
    private var keysFound = 0
    private var battery: Float = 1
    private var elapsed: Float = 0
    private var lastTime: TimeInterval = 0
    private var bobPhase: Float = 0
    private var heartbeatTimer: Float = 0
    private var ambientTimer: Float = 6
    private var hudTimer: Float = 0
    private var nearDoor = false
    private var danger: Float = 0

    // Touch input, written on the main thread and read by the render thread.
    private let inputLock = NSLock()
    private var moveInput = CGPoint.zero
    private var lookDelta = CGPoint.zero
    private var moveTouch: UITouch?
    private var lookTouch: UITouch?
    private var moveOrigin = CGPoint.zero
    private var lastLook = CGPoint.zero

    // HUD
    private let vignette = UIImageView()
    private let dangerVignette = UIImageView()
    private let keysLabel = UILabel(text: "KEYS 0/3", size: 18, bold: true)
    private let batteryFrame = UIView()
    private let batteryFill = UIView()
    private let messageLabel = UILabel(text: "", size: 22, bold: true)
    private let stickBase = UIView()
    private let stickKnob = UIView()
    private let overlay = UIView()
    private let overlayTitle = UILabel(text: "", size: 54, bold: true)
    private let overlayText = UILabel(text: "", size: 20, color: Palette.dimText)

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.isMultipleTouchEnabled = true

        scnView.frame = view.bounds
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor = .black
        scnView.antialiasingMode = .none
        scnView.preferredFramesPerSecond = 30
        scnView.isMultipleTouchEnabled = true
        scnView.scene = scene
        view.addSubview(scnView)

        buildHouse()
        buildPlayer()
        buildHUD()
        resetGame()
        showOverlay(title: "THE HOUSE",
                    text: "Find the 3 keys and escape through the front door.\nSomething else is in the house. If it sees you, run.\n\nLeft side: walk (push all the way to run — it can hear running)\nRight side: look around\n\nHeadphones recommended.  Tap to begin.")

        scnView.pointOfView = camera
        scnView.delegate = self
        scnView.isPlaying = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scnView.isPlaying = false
        audio.stop()
    }

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    // MARK: - Building the house

    private func material(_ image: UIImage, repeatX: Float = 1, repeatY: Float = 1,
                          lighting: SCNMaterial.LightingModel = .lambert) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.diffuse.mipFilter = .linear
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(repeatX, repeatY, 1)
        m.lightingModel = lighting
        return m
    }

    private func buildHouse() {
        let root = scene.rootNode
        let cell = HorrorMap.cell
        let width = Float(map.width) * cell, depth = Float(map.height) * cell

        scene.fogStartDistance = 0.5
        scene.fogEndDistance = 15
        scene.fogDensityExponent = 1.3
        scene.fogColor = UIColor.black
        scene.background.contents = UIColor.black

        let floorMaterial = material(HorrorTextures.floorboards(), repeatX: Float(map.width), repeatY: Float(map.height),
                                     lighting: .blinn)
        floorMaterial.specular.contents = UIColor(white: 0.15, alpha: 1)
        let floor = SCNNode(geometry: SCNPlane(width: CGFloat(width), height: CGFloat(depth)))
        floor.geometry?.firstMaterial = floorMaterial
        floor.eulerAngles.x = -.pi / 2
        floor.position = SCNVector3(width / 2, 0, depth / 2)
        root.addChildNode(floor)

        let ceiling = SCNNode(geometry: SCNPlane(width: CGFloat(width), height: CGFloat(depth)))
        ceiling.geometry?.firstMaterial = material(HorrorTextures.ceiling(), repeatX: Float(map.width), repeatY: Float(map.height))
        ceiling.eulerAngles.x = .pi / 2
        ceiling.position = SCNVector3(width / 2, HorrorMap.wallHeight, depth / 2)
        root.addChildNode(ceiling)

        // Walls: only cells that face a room, merged into one node so an old GPU copes.
        let wallBox = SCNBox(width: CGFloat(cell), height: CGFloat(HorrorMap.wallHeight), length: CGFloat(cell), chamferRadius: 0)
        wallBox.firstMaterial = material(HorrorTextures.wallpaper())
        let walls = SCNNode()
        var faces: [(GridPoint, Int, Int)] = []
        for row in 0..<map.height {
            for col in 0..<map.width {
                let p = GridPoint(col: col, row: row)
                guard map.isWall(p) else { continue }
                var facesRoom = false
                for dr in -1...1 {
                    for dc in -1...1 where !map.isWall(GridPoint(col: col + dc, row: row + dr)) {
                        facesRoom = true
                        if abs(dc) + abs(dr) == 1 && map.character(at: p) == "#" {
                            faces.append((GridPoint(col: col + dc, row: row + dr), dc, dr))
                        }
                    }
                }
                guard facesRoom else { continue }
                let block = SCNNode(geometry: wallBox)
                block.position = map.center(p, y: HorrorMap.wallHeight / 2)
                walls.addChildNode(block)
            }
        }
        root.addChildNode(walls.flattenedClone())

        let wood = material(HorrorTextures.darkWood(), lighting: .blinn)
        wood.specular.contents = UIColor(white: 0.1, alpha: 1)
        buildTables(wood)
        buildPortraits(faces: faces, wood: wood)
        buildDoor(wood)
        buildPickups(wood)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = UIColor(red: 0.45, green: 0.5, blue: 0.7, alpha: 1)
        ambient.light?.intensity = 22
        root.addChildNode(ambient)

        root.addChildNode(creature.node)
        creature.onStep = { [weak self] position in self?.creatureStepped(at: position) }
        creature.onSpotted = { [weak self] in
            guard let self = self else { return }
            self.audio.whisper(volume: 1, pan: 0)
            DispatchQueue.main.async { self.showMessage("It sees you. RUN.") }
        }
    }

    private func buildTables(_ wood: SCNMaterial) {
        let tables = SCNNode()
        for p in map.tables {
            let c = map.center(p)
            let top = SCNNode(geometry: SCNBox(width: 2, height: 0.08, length: 1.2, chamferRadius: 0.01))
            top.position = SCNVector3(c.x, 0.78, c.z)
            tables.addChildNode(top)
            for (lx, lz) in [(-0.9, -0.5), (0.9, -0.5), (-0.9, 0.5), (0.9, 0.5)] as [(Float, Float)] {
                let leg = SCNNode(geometry: SCNCylinder(radius: 0.04, height: 0.78))
                leg.position = SCNVector3(c.x + lx, 0.39, c.z + lz)
                tables.addChildNode(leg)
            }
        }
        tables.enumerateHierarchy { node, _ in node.geometry?.firstMaterial = wood }
        scene.rootNode.addChildNode(tables.flattenedClone())
    }

    private func buildPortraits(faces: [(GridPoint, Int, Int)], wood: SCNMaterial) {
        let picture = material(HorrorTextures.portrait())
        let frames = SCNNode()
        for (floorCell, dc, dr) in faces.shuffled().prefix(12) {
            // (dc, dr) points from the wall back into the room.
            let c = map.center(floorCell)
            let inset = HorrorMap.cell / 2 - 0.03
            let frame = SCNNode(geometry: SCNBox(width: 0.85, height: 1.05, length: 0.05, chamferRadius: 0))
            frame.geometry?.firstMaterial = wood
            frame.position = SCNVector3(c.x - Float(dc) * inset, 1.75, c.z - Float(dr) * inset)
            frame.eulerAngles.y = atan2(Float(dc), Float(dr))
            frame.eulerAngles.z = Float.random(in: -0.06...0.06)
            let canvas = SCNNode(geometry: SCNPlane(width: 0.68, height: 0.86))
            canvas.geometry?.firstMaterial = picture
            canvas.position = SCNVector3(0, 0, 0.03)
            frame.addChildNode(canvas)
            frames.addChildNode(frame)
        }
        scene.rootNode.addChildNode(frames.flattenedClone())
    }

    private func buildDoor(_ wood: SCNMaterial) {
        let inside = map.exitInside
        let dc = Float(inside.col - map.exit.col), dr = Float(inside.row - map.exit.row)
        let c = map.center(map.exit)
        let face = HorrorMap.cell / 2 + 0.03
        let door = SCNNode(geometry: SCNBox(width: 1.3, height: 2.25, length: 0.08, chamferRadius: 0))
        door.geometry?.firstMaterial = wood
        door.position = SCNVector3(c.x + dc * face, 1.125, c.z + dr * face)
        door.eulerAngles.y = atan2(dc, dr)

        let brass = SCNMaterial()
        brass.diffuse.contents = UIColor(red: 0.6, green: 0.45, blue: 0.2, alpha: 1)
        brass.specular.contents = UIColor.white
        brass.lightingModel = .blinn
        let knob = SCNNode(geometry: SCNSphere(radius: 0.045))
        knob.geometry?.firstMaterial = brass
        knob.position = SCNVector3(0.5, 0, 0.07)
        door.addChildNode(knob)

        // Pale moonlight leaking under the door: the way out.
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = UIColor(red: 0.45, green: 0.55, blue: 0.75, alpha: 1)
        let gap = SCNNode(geometry: SCNBox(width: 1.25, height: 0.025, length: 0.02, chamferRadius: 0))
        gap.geometry?.firstMaterial = glow
        gap.position = SCNVector3(0, -1.115, 0.05)
        door.addChildNode(gap)
        scene.rootNode.addChildNode(door)

        doorPoint = SCNVector3(c.x + dc * (HorrorMap.cell / 2 + 0.9), 0, c.z + dr * (HorrorMap.cell / 2 + 0.9))
    }

    private func buildPickups(_ wood: SCNMaterial) {
        let brass = SCNMaterial()
        brass.diffuse.contents = UIColor(red: 0.78, green: 0.62, blue: 0.28, alpha: 1)
        brass.emission.contents = UIColor(red: 0.22, green: 0.16, blue: 0.05, alpha: 1)
        brass.specular.contents = UIColor.white
        brass.lightingModel = .blinn

        let cellMaterial = SCNMaterial()
        cellMaterial.diffuse.contents = UIColor(white: 0.15, alpha: 1)
        cellMaterial.emission.contents = UIColor(red: 0.04, green: 0.12, blue: 0.05, alpha: 1)
        cellMaterial.specular.contents = UIColor.white
        cellMaterial.lightingModel = .blinn

        let spin = SCNAction.repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 5))

        func stool(at p: GridPoint) {
            let s = SCNNode(geometry: SCNBox(width: 0.45, height: 0.85, length: 0.45, chamferRadius: 0.02))
            s.geometry?.firstMaterial = wood
            s.position = map.center(p, y: 0.425)
            scene.rootNode.addChildNode(s)
        }

        for p in map.keys {
            stool(at: p)
            let key = SCNNode()
            let ring = SCNNode(geometry: SCNTorus(ringRadius: 0.05, pipeRadius: 0.013))
            ring.eulerAngles.x = .pi / 2
            ring.position = SCNVector3(-0.1, 0, 0)
            let shaft = SCNNode(geometry: SCNBox(width: 0.16, height: 0.018, length: 0.018, chamferRadius: 0))
            shaft.position = SCNVector3(0.03, 0, 0)
            let teeth = SCNNode(geometry: SCNBox(width: 0.04, height: 0.05, length: 0.018, chamferRadius: 0))
            teeth.position = SCNVector3(0.09, -0.03, 0)
            for part in [ring, shaft, teeth] {
                part.geometry?.firstMaterial = brass
                key.addChildNode(part)
            }
            key.position = map.center(p, y: 0.97)
            key.runAction(spin)
            scene.rootNode.addChildNode(key)
            keyNodes[p] = key
        }

        for p in map.batteries {
            stool(at: p)
            let cell = SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.14))
            cell.geometry?.firstMaterial = cellMaterial
            cell.eulerAngles.z = .pi / 2
            let holder = SCNNode()
            holder.addChildNode(cell)
            holder.position = map.center(p, y: 0.9)
            holder.runAction(spin)
            scene.rootNode.addChildNode(holder)
            batteryNodes[p] = holder
        }
    }

    private func buildPlayer() {
        let cam = SCNCamera()
        cam.zNear = 0.05
        cam.zFar = 40
        cam.fieldOfView = 68
        camera.camera = cam
        camera.position = SCNVector3(0, 1.6, 0)
        player.addChildNode(camera)

        flashlight.type = .spot
        flashlight.color = UIColor(red: 1, green: 0.93, blue: 0.8, alpha: 1)
        flashlight.spotInnerAngle = 18
        flashlight.spotOuterAngle = 48
        flashlight.attenuationStartDistance = 0
        flashlight.attenuationEndDistance = 17
        flashlight.attenuationFalloffExponent = 2
        flashlight.castsShadow = true
        flashlight.shadowMapSize = CGSize(width: 512, height: 512)
        flashlight.shadowSampleCount = 1
        flashlight.shadowRadius = 2
        flashlight.shadowColor = UIColor(white: 0, alpha: 0.85)
        let lamp = SCNNode()
        lamp.light = flashlight
        lamp.position = SCNVector3(0.18, -0.2, 0)
        camera.addChildNode(lamp)

        // Dust hanging in the air, only visible where the torch beam hits it.
        let dust = SCNParticleSystem()
        dust.birthRate = 25
        dust.particleLifeSpan = 7
        dust.emitterShape = SCNBox(width: 7, height: 2.6, length: 7, chamferRadius: 0)
        dust.birthLocation = .volume
        dust.particleSize = 0.006
        dust.particleVelocity = 0.04
        dust.particleVelocityVariation = 0.04
        dust.particleColor = UIColor(white: 1, alpha: 0.5)
        dust.isLightingEnabled = true
        dust.blendMode = .additive
        dust.loops = true
        let dustNode = SCNNode()
        dustNode.position = SCNVector3(0, 1.4, 0)
        dustNode.addParticleSystem(dust)
        player.addChildNode(dustNode)

        scene.rootNode.addChildNode(player)
    }

    // MARK: - HUD

    private func buildHUD() {
        let size = view.bounds.size
        for (imageView, tint) in [(vignette, UIColor.black), (dangerVignette, UIColor(red: 0.5, green: 0, blue: 0, alpha: 1))] {
            imageView.image = HorrorTextures.vignette(size: CGSize(width: 512, height: 384), tint: tint)
            imageView.frame = view.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(imageView)
        }
        dangerVignette.alpha = 0

        keysLabel.textAlignment = .left
        keysLabel.frame = CGRect(x: 24, y: 20, width: 200, height: 26)
        view.addSubview(keysLabel)

        batteryFrame.frame = CGRect(x: 24, y: 52, width: 124, height: 14)
        batteryFrame.layer.borderColor = UIColor(white: 1, alpha: 0.6).cgColor
        batteryFrame.layer.borderWidth = 1
        batteryFrame.layer.cornerRadius = 3
        batteryFill.backgroundColor = UIColor(white: 0.9, alpha: 0.8)
        batteryFrame.addSubview(batteryFill)
        view.addSubview(batteryFrame)

        messageLabel.frame = CGRect(x: 40, y: size.height - 120, width: size.width - 80, height: 60)
        messageLabel.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
        messageLabel.alpha = 0
        view.addSubview(messageLabel)

        stickBase.frame = CGRect(x: 0, y: 0, width: 140, height: 140)
        stickBase.layer.cornerRadius = 70
        stickBase.layer.borderWidth = 2
        stickBase.layer.borderColor = UIColor(white: 1, alpha: 0.25).cgColor
        stickKnob.frame = CGRect(x: 0, y: 0, width: 56, height: 56)
        stickKnob.layer.cornerRadius = 28
        stickKnob.backgroundColor = UIColor(white: 1, alpha: 0.2)
        for v in [stickBase, stickKnob] {
            v.isHidden = true
            v.isUserInteractionEnabled = false
            view.addSubview(v)
        }

        let menu = ActionButton("‹ MENU", fontSize: 16) { [weak self] in self?.dismiss(animated: true) }
        menu.frame = CGRect(x: size.width - 124, y: 18, width: 104, height: 40)
        menu.autoresizingMask = [.flexibleLeftMargin]
        menu.alpha = 0.7
        view.addSubview(menu)

        overlay.frame = view.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = UIColor(white: 0, alpha: 0.88)
        let stack = UIStackView([overlayTitle, overlayText], axis: .vertical, spacing: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stack.widthAnchor.constraint(equalTo: overlay.widthAnchor, multiplier: 0.75),
        ])
        view.insertSubview(overlay, belowSubview: menu)
    }

    private func showOverlay(title: String, text: String, color: UIColor = Palette.text) {
        overlayTitle.text = title
        overlayTitle.textColor = color
        overlayText.text = text
        overlay.alpha = 0
        overlay.isHidden = false
        UIView.animate(withDuration: 0.6) { self.overlay.alpha = 1 }
    }

    private func showMessage(_ text: String) {
        messageLabel.layer.removeAllAnimations()
        messageLabel.text = text
        messageLabel.alpha = 1
        UIView.animate(withDuration: 1, delay: 2.2, options: [], animations: { self.messageLabel.alpha = 0 })
    }

    private func updateHUD(keys: Int, battery: Float, danger: Float) {
        keysLabel.text = "KEYS \(keys)/\(map.keys.count)"
        batteryFill.frame = CGRect(x: 2, y: 2, width: CGFloat(battery) * 120, height: 10)
        batteryFill.backgroundColor = battery < 0.2 ? Palette.error : UIColor(white: 0.9, alpha: 0.8)
        dangerVignette.alpha = CGFloat(danger) * 0.7
    }

    // MARK: - Touch controls

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard phase == .playing else {
            overlayTapped()
            return
        }
        for touch in touches {
            let p = touch.location(in: view)
            if p.x < view.bounds.width * 0.4 && moveTouch == nil {
                moveTouch = touch
                moveOrigin = p
                stickBase.center = p
                stickKnob.center = p
                stickBase.isHidden = false
                stickKnob.isHidden = false
            } else if lookTouch == nil {
                lookTouch = touch
                lastLook = p
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let p = touch.location(in: view)
            if touch === moveTouch {
                var dx = p.x - moveOrigin.x, dy = p.y - moveOrigin.y
                let length = hypot(dx, dy)
                if length > 70 {
                    dx *= 70 / length
                    dy *= 70 / length
                }
                stickKnob.center = CGPoint(x: moveOrigin.x + dx, y: moveOrigin.y + dy)
                inputLock.lock()
                moveInput = CGPoint(x: dx / 70, y: dy / 70)
                inputLock.unlock()
            } else if touch === lookTouch {
                inputLock.lock()
                lookDelta.x += p.x - lastLook.x
                lookDelta.y += p.y - lastLook.y
                inputLock.unlock()
                lastLook = p
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch === moveTouch {
                moveTouch = nil
                stickBase.isHidden = true
                stickKnob.isHidden = true
                inputLock.lock()
                moveInput = .zero
                inputLock.unlock()
            } else if touch === lookTouch {
                lookTouch = nil
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    private func overlayTapped() {
        switch phase {
        case .intro:
            beginPlaying()
        case .caught, .escaped:
            // Ignore taps until the ending has had a moment on screen.
            guard !overlay.isHidden, overlay.alpha > 0.9 else { return }
            resetGame()
            beginPlaying()
        case .playing:
            break
        }
    }

    private func beginPlaying() {
        UIView.animate(withDuration: 0.5, animations: { self.overlay.alpha = 0 }) { _ in self.overlay.isHidden = true }
        audio.startAmbience()
        lastTime = 0
        phase = .playing
        showMessage("Where am I…?")
    }

    private func resetGame() {
        keysFound = 0
        battery = 1
        elapsed = 0
        danger = 0
        nearDoor = false
        keyNodes.values.forEach { $0.isHidden = false }
        batteryNodes.values.forEach { $0.isHidden = false }
        yaw = -.pi / 2
        pitch = 0
        player.position = map.center(map.playerStart)
        player.eulerAngles.y = yaw
        camera.eulerAngles.x = 0
        camera.position = SCNVector3(0, 1.6, 0)
        creature.reset(at: map.center(map.monsterStart))
        inputLock.lock()
        moveInput = .zero
        lookDelta = .zero
        inputLock.unlock()
        updateHUD(keys: 0, battery: 1, danger: 0)
    }

    // MARK: - Game loop (SceneKit render thread)

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime == 0 ? 0 : Float(min(time - lastTime, 0.1))
        lastTime = time
        guard phase == .playing, dt > 0 else { return }
        elapsed += dt

        inputLock.lock()
        let move = moveInput
        let look = lookDelta
        lookDelta = .zero
        inputLock.unlock()

        // Looking
        yaw -= Float(look.x) * 0.006
        pitch = max(-1.1, min(1.1, pitch - Float(look.y) * 0.005))
        player.eulerAngles.y = yaw
        camera.eulerAngles.x = pitch

        // Walking: push the stick all the way to run.
        let mx = Float(move.x), my = Float(move.y)
        let amount = min(1, sqrt(mx * mx + my * my))
        let running = amount > 0.92
        let speed: Float = running ? 3.3 : 1.8
        let forward = (x: -sin(yaw), z: -cos(yaw))
        let right = (x: cos(yaw), z: -sin(yaw))
        let dx = (right.x * mx - forward.x * my) * speed * dt
        let dz = (right.z * mx - forward.z * my) * speed * dt
        let resolved = map.resolve(x: player.position.x + dx, z: player.position.z + dz, radius: 0.35)
        player.position = SCNVector3(resolved.0, 0, resolved.1)

        // Head bob and footsteps.
        if amount > 0.1 {
            let before = Int(bobPhase / .pi)
            bobPhase += dt * (running ? 10.5 : 7) * amount
            if Int(bobPhase / .pi) != before { audio.footstep(volume: running ? 0.9 : 0.5) }
        }
        camera.position.y = 1.6 + abs(sin(bobPhase)) * (running ? 0.07 : 0.04) - 0.02

        let here = player.position
        updatePickups(at: here)
        updateDoor(at: here)
        if phase != .playing { return }

        creature.update(dt: dt, player: here, playerRunning: running, keysFound: keysFound, map: map)
        let cx = creature.node.position.x - here.x, cz = creature.node.position.z - here.z
        let creatureDistance = sqrt(cx * cx + cz * cz)
        if creatureDistance < 0.95 {
            caught()
            return
        }
        danger = max(0, min(1, (11 - creatureDistance) / 9))
        if creature.isHunting { danger = max(danger, 0.35) }

        updateFlashlight(dt: dt)
        updateSounds(dt: dt)

        hudTimer -= dt
        if hudTimer <= 0 {
            hudTimer = 0.15
            let keys = keysFound, charge = battery, threat = danger
            DispatchQueue.main.async { self.updateHUD(keys: keys, battery: charge, danger: threat) }
        }
    }

    private func updatePickups(at here: SCNVector3) {
        for (p, node) in keyNodes where !node.isHidden {
            let c = map.center(p)
            if hypot(c.x - here.x, c.z - here.z) < 1.3 {
                node.isHidden = true
                keysFound += 1
                audio.pickup()
                let found = keysFound, total = map.keys.count
                DispatchQueue.main.async {
                    self.showMessage(found == total ? "That's all the keys. Get to the front door!" : "Found a key (\(found)/\(total))")
                }
            }
        }
        for (p, node) in batteryNodes where !node.isHidden {
            let c = map.center(p)
            if hypot(c.x - here.x, c.z - here.z) < 1.3 {
                node.isHidden = true
                battery = 1
                audio.pickup()
                DispatchQueue.main.async { self.showMessage("Fresh batteries") }
            }
        }
    }

    private func updateDoor(at here: SCNVector3) {
        let atDoor = hypot(doorPoint.x - here.x, doorPoint.z - here.z) < 1.4
        defer { nearDoor = atDoor }
        guard atDoor, !nearDoor else { return }
        if keysFound == map.keys.count {
            escaped()
        } else {
            audio.lockedDoor()
            let missing = map.keys.count - keysFound
            DispatchQueue.main.async { self.showMessage("The front door is locked. \(missing) more key\(missing == 1 ? "" : "s")…") }
        }
    }

    private func updateFlashlight(dt: Float) {
        battery = max(0, battery - dt / 160)
        var intensity: CGFloat = battery > 0 ? 1800 * CGFloat(0.35 + 0.65 * battery) : 220
        let flickerChance = (battery < 0.2 ? 0.08 : 0.01) + danger * 0.12
        if Float.random(in: 0...1) < flickerChance {
            intensity *= CGFloat.random(in: 0.05...0.6)
        }
        flashlight.intensity = intensity
    }

    private func updateSounds(dt: Float) {
        heartbeatTimer -= dt
        if danger > 0.05 && heartbeatTimer <= 0 {
            audio.heartbeat(volume: 0.25 + 0.75 * danger)
            heartbeatTimer = 1.15 - 0.7 * danger
        }

        ambientTimer -= dt
        if ambientTimer <= 0 {
            ambientTimer = Float.random(in: 7...16)
            let pan = Float.random(in: -1...1)
            if Bool.random() {
                audio.creak(volume: .random(in: 0.3...0.7), pan: pan)
            } else {
                audio.whisper(volume: .random(in: 0.15...0.4), pan: pan)
            }
        }
    }

    private func creatureStepped(at position: SCNVector3) {
        let here = player.position
        let dx = position.x - here.x, dz = position.z - here.z
        let distance = sqrt(dx * dx + dz * dz)
        guard distance < 20 else { return }
        var volume = pow(max(0, 1 - distance / 20), 1.5)
        if !map.hasLineOfSight(from: here, to: position) { volume *= 0.5 }
        let right = (x: cos(yaw), z: -sin(yaw))
        let pan = distance > 0.01 ? (dx * right.x + dz * right.z) / distance : 0
        audio.creatureStep(volume: volume, pan: pan)
    }

    // MARK: - Endings

    private func caught() {
        phase = .caught
        flashlight.intensity = 2200
        // Spin the view round to face it, right where it caught you.
        let here = player.position
        var tx = creature.node.position.x - here.x, tz = creature.node.position.z - here.z
        let length = max(0.01, sqrt(tx * tx + tz * tz))
        tx /= length
        tz /= length
        yaw = atan2(-tx, -tz)
        player.eulerAngles.y = yaw
        creature.lunge(at: SCNVector3(here.x + tx * 0.75, 0, here.z + tz * 0.75), facingYaw: yaw + .pi)
        camera.eulerAngles.x = 0.6
        audio.scream()

        var shake: [SCNAction] = []
        for _ in 0..<10 {
            let jolt = SCNVector3(Float.random(in: -0.05...0.05), Float.random(in: -0.05...0.05), 0)
            shake.append(.move(by: jolt, duration: 0.04))
            shake.append(.move(by: SCNVector3(-jolt.x, -jolt.y, 0), duration: 0.04))
        }
        camera.runAction(.sequence(shake))

        DispatchQueue.main.async {
            self.dangerVignette.alpha = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                self.showOverlay(title: "IT CAUGHT YOU",
                                 text: "Keys found: \(self.keysFound)/\(self.map.keys.count)\n\nTap to try again.",
                                 color: Palette.error)
            }
        }
    }

    private func escaped() {
        phase = .escaped
        let seconds = Int(elapsed)
        DispatchQueue.main.async {
            self.showOverlay(title: "YOU ESCAPED",
                             text: "You got out in \(seconds / 60):\(String(format: "%02d", seconds % 60)).\nThe door slams shut behind you.\n\nTap to play again.")
        }
    }
}
