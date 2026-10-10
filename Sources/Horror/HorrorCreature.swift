import SceneKit

/// The tall thing that walks the house. It wanders until it sees the player
/// (or hears them running), then hunts them along the shortest route.
final class HorrorCreature {
    let node = SCNNode()
    var onStep: ((SCNVector3) -> Void)?
    var onSpotted: (() -> Void)?

    private(set) var isHunting = false
    private let body = SCNNode()
    private let eyeMaterial = SCNMaterial()
    private var path: [GridPoint] = []
    private var lostSight: Float = 0
    private var repath: Float = 0
    private var stepTimer: Float = 0
    private var time: Float = 0
    private var facing: Float = 0

    /// It stays still for the first few seconds so the player can get their bearings.
    private let wakesAfter: Float = 12

    init() {
        let skin = SCNMaterial()
        skin.diffuse.contents = UIColor(red: 0.035, green: 0.03, blue: 0.035, alpha: 1)
        skin.specular.contents = UIColor(white: 0.35, alpha: 1)
        skin.shininess = 0.6
        skin.lightingModel = .blinn

        func part(_ geometry: SCNGeometry, _ position: SCNVector3, scale: SCNVector3 = SCNVector3(1, 1, 1),
                  roll: Float = 0) -> SCNNode {
            geometry.firstMaterial = skin
            let n = SCNNode(geometry: geometry)
            n.position = position
            n.scale = scale
            n.eulerAngles.z = roll
            body.addChildNode(n)
            return n
        }
        part(SCNCapsule(capRadius: 0.2, height: 1.25), SCNVector3(0, 1.4, 0), scale: SCNVector3(0.85, 1, 0.6))
        part(SCNSphere(radius: 0.16), SCNVector3(0, 2.18, -0.03), scale: SCNVector3(0.85, 1.25, 0.9))
        part(SCNCylinder(radius: 0.04, height: 1.3), SCNVector3(-0.27, 1.2, -0.05), roll: -0.12)
        part(SCNCylinder(radius: 0.04, height: 1.3), SCNVector3(0.27, 1.2, -0.05), roll: 0.12)
        part(SCNCylinder(radius: 0.055, height: 0.95), SCNVector3(-0.1, 0.48, 0))
        part(SCNCylinder(radius: 0.055, height: 0.95), SCNVector3(0.1, 0.48, 0))

        eyeMaterial.lightingModel = .constant
        eyeMaterial.diffuse.contents = UIColor(white: 0.85, alpha: 1)
        for x: Float in [-0.055, 0.055] {
            let eye = SCNNode(geometry: SCNSphere(radius: 0.02))
            eye.geometry?.firstMaterial = eyeMaterial
            eye.position = SCNVector3(x, 2.22, -0.17)
            body.addChildNode(eye)
        }
        node.addChildNode(body)
    }

    func reset(at position: SCNVector3) {
        node.position = position
        path = []
        isHunting = false
        lostSight = 0
        time = 0
        setEyes(hunting: false)
    }

    /// Plants it right in front of the camera for the jump scare.
    func lunge(at position: SCNVector3, facingYaw yaw: Float) {
        node.position = position
        node.eulerAngles.y = yaw
        setEyes(hunting: true)
    }

    func update(dt: Float, player: SCNVector3, playerRunning: Bool, keysFound: Int, map: HorrorMap) {
        time += dt
        body.eulerAngles.z = sin(time * 1.3) * 0.05
        body.childNodes[1].eulerAngles.z = sin(time * 7.1) * sin(time * 0.9) * 0.15   // head twitch
        guard time > wakesAfter else { return }

        let here = node.position
        let dx = player.x - here.x, dz = player.z - here.z
        let distance = sqrt(dx * dx + dz * dz)
        let eyes = SCNVector3(here.x, 2.2, here.z)
        let sees = distance < 14 && map.hasLineOfSight(from: eyes, to: player)
        let hears = distance < (playerRunning ? 11 : 3)

        if sees || hears {
            if !isHunting {
                isHunting = true
                setEyes(hunting: true)
                onSpotted?()
            }
            lostSight = 0
        } else if isHunting {
            lostSight += dt
            if lostSight > 7 {
                isHunting = false
                path = []
                setEyes(hunting: false)
            }
        }

        let cell = map.gridPoint(x: here.x, z: here.z)
        repath -= dt
        if isHunting && repath <= 0 {
            path = map.path(from: cell, to: map.gridPoint(x: player.x, z: player.z))
            repath = 0.4
        }
        if !isHunting && path.isEmpty, let goal = map.walkable.randomElement() {
            path = map.path(from: cell, to: goal)
        }

        // Close and in plain sight it comes straight at you; otherwise it follows the route.
        var target: SCNVector3?
        if isHunting && sees && distance < 5 || isHunting && path.isEmpty {
            target = player
        } else if let next = path.first {
            let c = map.center(next)
            if abs(c.x - here.x) < 0.25 && abs(c.z - here.z) < 0.25 {
                path.removeFirst()
            }
            target = path.first.map { map.center($0) } ?? c
        }

        let speed: Float = isHunting ? 2.1 + Float(keysFound) * 0.12 : 1.0
        if let target = target {
            let tx = target.x - here.x, tz = target.z - here.z
            let length = sqrt(tx * tx + tz * tz)
            if length > 0.01 {
                let step = min(length, speed * dt)
                node.position = SCNVector3(here.x + tx / length * step, 0, here.z + tz / length * step)
                let wanted = atan2(-tx, -tz)
                var turn = wanted - facing
                while turn > .pi { turn -= 2 * .pi }
                while turn < -.pi { turn += 2 * .pi }
                facing += turn * min(1, dt * 6)
                node.eulerAngles.y = facing
            }
        }

        stepTimer -= dt
        if stepTimer <= 0 {
            stepTimer = isHunting ? 0.36 : 0.75
            onStep?(node.position)
        }
    }

    private func setEyes(hunting: Bool) {
        eyeMaterial.diffuse.contents = hunting
            ? UIColor(red: 1, green: 0.12, blue: 0.08, alpha: 1)
            : UIColor(white: 0.85, alpha: 1)
    }
}
