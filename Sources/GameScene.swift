import SpriteKit

// MARK: - Physics categories

private struct PhysicsCategory {
    static let none: UInt32     = 0
    static let player: UInt32   = 0x1 << 0
    static let ground: UInt32   = 0x1 << 1
    static let obstacle: UInt32 = 0x1 << 2
}

/// SIGNAL RUNNER — a tiny, dependency-free 2D dodge-the-obstacle game.
/// Everything is drawn with SKShapeNode primitives (no image assets, no
/// shaders, no particle emitters) so it stays light enough for A7/A8-class
/// iPads still running iOS 12.
final class GameScene: SKScene, SKPhysicsContactDelegate {

    // Nodes
    private var player: SKShapeNode!
    private var scoreLabel: SKLabelNode!
    private var hintLabel: SKLabelNode?
    private var overlayLabel: SKLabelNode?
    private var farHills = SKNode()
    private var nearHills = SKNode()

    // State
    private var isPlaying = false
    private var isGameOver = false
    private var score = 0
    private var distance: CGFloat = 0
    private var scrollSpeed: CGFloat = 220
    private var lastUpdateTime: TimeInterval = 0
    private var obstacleTimer: TimeInterval = 0
    private var nextObstacleInterval: TimeInterval = 1.4
    private var onGround = true
    private var bestScore = UserDefaults.standard.integer(forKey: "bestScore")

    private let groundHeightFraction: CGFloat = 0.22

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.53, green: 0.75, blue: 0.94, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.2)
        physicsWorld.contactDelegate = self
        scaleMode = .resizeFill

        buildBackground()
        buildGround()
        buildPlayer()
        buildHUD()
        showStartPrompt()
    }

    private func buildBackground() {
        addChild(farHills)
        addChild(nearHills)
        layoutHillLayer(farHills, color: SKColor(red: 0.62, green: 0.80, blue: 0.60, alpha: 1), heightFraction: 0.14, count: 6)
        layoutHillLayer(nearHills, color: SKColor(red: 0.44, green: 0.68, blue: 0.45, alpha: 1), heightFraction: 0.20, count: 5)
    }

    private func layoutHillLayer(_ layer: SKNode, color: SKColor, heightFraction: CGFloat, count: Int) {
        let groundY = frame.minY + frame.height * groundHeightFraction
        let hillWidth = frame.width * 0.9
        for i in 0..<count {
            let hill = SKShapeNode(ellipseOf: CGSize(width: hillWidth, height: frame.height * heightFraction * 2))
            hill.fillColor = color
            hill.strokeColor = .clear
            hill.position = CGPoint(x: CGFloat(i) * hillWidth * 0.8, y: groundY)
            hill.zPosition = -10
            layer.addChild(hill)
        }
    }

    private func buildGround() {
        let groundY = frame.minY + frame.height * groundHeightFraction
        let groundNode = SKShapeNode(rect: CGRect(x: frame.minX - 40, y: frame.minY,
                                                   width: frame.width + 80, height: groundY - frame.minY))
        groundNode.fillColor = SKColor(red: 0.36, green: 0.24, blue: 0.16, alpha: 1)
        groundNode.strokeColor = .clear
        groundNode.zPosition = -1
        groundNode.physicsBody = SKPhysicsBody(edgeFrom: CGPoint(x: frame.minX - 40, y: groundY),
                                                to: CGPoint(x: frame.maxX + 40, y: groundY))
        groundNode.physicsBody?.categoryBitMask = PhysicsCategory.ground
        groundNode.physicsBody?.collisionBitMask = PhysicsCategory.player
        groundNode.physicsBody?.contactTestBitMask = PhysicsCategory.player
        groundNode.physicsBody?.friction = 0
        addChild(groundNode)
    }

    private func buildPlayer() {
        let groundY = frame.minY + frame.height * groundHeightFraction
        let size = min(frame.width, frame.height) * 0.07
        player = SKShapeNode(rectOf: CGSize(width: size, height: size), cornerRadius: size * 0.25)
        player.fillColor = SKColor(red: 1.0, green: 0.83, blue: 0.30, alpha: 1)
        player.strokeColor = SKColor(red: 0.6, green: 0.45, blue: 0.05, alpha: 1)
        player.lineWidth = 2
        player.position = CGPoint(x: frame.minX + frame.width * 0.24, y: groundY + size * 0.5)
        player.zPosition = 5
        player.physicsBody = SKPhysicsBody(rectangleOf: player.frame.size)
        player.physicsBody?.categoryBitMask = PhysicsCategory.player
        player.physicsBody?.collisionBitMask = PhysicsCategory.ground
        player.physicsBody?.contactTestBitMask = PhysicsCategory.ground | PhysicsCategory.obstacle
        player.physicsBody?.allowsRotation = false
        player.physicsBody?.restitution = 0
        player.physicsBody?.linearDamping = 0
        addChild(player)
    }

    private func buildHUD() {
        scoreLabel = SKLabelNode(fontNamed: "Menlo-Bold")
        scoreLabel.fontSize = 22
        scoreLabel.fontColor = .white
        scoreLabel.horizontalAlignmentMode = .left
        scoreLabel.position = CGPoint(x: frame.minX + 20, y: frame.maxY - 44)
        scoreLabel.zPosition = 20
        scoreLabel.text = "0"
        addChild(scoreLabel)
    }

    private func showStartPrompt() {
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.fontSize = 20
        label.fontColor = .white
        label.numberOfLines = 2
        label.text = "TAP TO START\nTAP TO JUMP"
        label.position = CGPoint(x: frame.midX, y: frame.midY)
        label.zPosition = 20
        addChild(label)
        hintLabel = label
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isGameOver { restart(); return }
        if !isPlaying { isPlaying = true; hintLabel?.removeFromParent(); return }
        jump()
    }

    private func jump() {
        guard onGround else { return }
        onGround = false
        player.physicsBody?.velocity = CGVector(dx: 0, dy: 0)
        player.physicsBody?.applyImpulse(CGVector(dx: 0, dy: frame.height * 0.11))
    }

    // MARK: - Obstacles

    private func spawnObstacle() {
        let groundY = frame.minY + frame.height * groundHeightFraction
        let h = CGFloat.random(in: frame.height * 0.05...frame.height * 0.11)
        let w = CGFloat.random(in: frame.width * 0.03...frame.width * 0.05)
        let obstacle = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: 3)
        obstacle.fillColor = SKColor(red: 0.85, green: 0.35, blue: 0.32, alpha: 1)
        obstacle.strokeColor = SKColor(red: 0.5, green: 0.15, blue: 0.12, alpha: 1)
        obstacle.position = CGPoint(x: frame.maxX + w, y: groundY + h / 2)
        obstacle.zPosition = 4
        obstacle.name = "obstacle"
        obstacle.physicsBody = SKPhysicsBody(rectangleOf: CGSize(width: w * 0.8, height: h * 0.9))
        obstacle.physicsBody?.isDynamic = false
        obstacle.physicsBody?.categoryBitMask = PhysicsCategory.obstacle
        obstacle.physicsBody?.collisionBitMask = PhysicsCategory.none
        obstacle.physicsBody?.contactTestBitMask = PhysicsCategory.player
        addChild(obstacle)
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        guard isPlaying, !isGameOver else { lastUpdateTime = currentTime; return }
        let dt = lastUpdateTime == 0 ? 0 : min(currentTime - lastUpdateTime, 1.0 / 30.0)
        lastUpdateTime = currentTime

        distance += scrollSpeed * CGFloat(dt)
        let newScore = Int(distance / 10)
        if newScore != score {
            score = newScore
            scoreLabel.text = "\(score)"
        }
        scrollSpeed = min(420, 220 + CGFloat(score) * 1.6)

        scrollLayer(farHills, factor: 0.25, dt: dt)
        scrollLayer(nearHills, factor: 0.55, dt: dt)

        for node in children where node.name == "obstacle" {
            node.position.x -= scrollSpeed * CGFloat(dt)
            if node.position.x < frame.minX - 80 { node.removeFromParent() }
        }

        obstacleTimer += dt
        if obstacleTimer >= nextObstacleInterval {
            obstacleTimer = 0
            nextObstacleInterval = Double.random(in: 0.9...1.6) * (220.0 / Double(scrollSpeed))
            spawnObstacle()
        }
    }

    private func scrollLayer(_ layer: SKNode, factor: CGFloat, dt: TimeInterval) {
        let step = frame.width * 0.9 * CGFloat(layer.children.count)
        for hill in layer.children {
            hill.position.x -= scrollSpeed * factor * CGFloat(dt)
            if hill.position.x < frame.minX - frame.width {
                hill.position.x += step
            }
        }
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        let mask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        if mask == (PhysicsCategory.player | PhysicsCategory.ground) {
            onGround = true
        } else if mask == (PhysicsCategory.player | PhysicsCategory.obstacle) {
            gameOver()
        }
    }

    // MARK: - Game over / restart

    private func gameOver() {
        guard !isGameOver else { return }
        isGameOver = true
        isPlaying = false
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: "bestScore")
        }
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.fontSize = 24
        label.fontColor = .white
        label.numberOfLines = 3
        label.text = "OUT — SCORE \(score)\nBEST \(bestScore)\nTAP TO RETRY"
        label.position = CGPoint(x: frame.midX, y: frame.midY)
        label.zPosition = 30
        addChild(label)
        overlayLabel = label
    }

    private func restart() {
        removeAllChildren()
        farHills = SKNode()
        nearHills = SKNode()
        isPlaying = false
        isGameOver = false
        score = 0
        distance = 0
        scrollSpeed = 220
        obstacleTimer = 0
        onGround = true
        lastUpdateTime = 0
        buildBackground()
        buildGround()
        buildPlayer()
        buildHUD()
        showStartPrompt()
    }
}
