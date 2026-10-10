import SceneKit

struct GridPoint: Hashable {
    let col: Int
    let row: Int
}

/// The house layout on a grid of 3 m cells, plus the geometry queries the
/// game needs: collision, line of sight and path-finding.
///
/// `#` wall · `.` floor · `d` doorway · `P` player start · `M` creature start
/// `K` key · `B` batteries · `T` table · `E` front door (in the outer wall)
final class HorrorMap {
    static let house = [
        "#################",
        "#P..T#.....#..K.#",
        "#....#.....#....#",
        "#..........d..T.#",
        "##d######d####d##",
        "#K..#...........#",
        "#...d.....M.....#",
        "#...#..T........#",
        "##d###d#######d##",
        "#.....#B...#....#",
        "#..B..d..K.d....E",
        "#T....#....#..T.#",
        "#################",
    ]

    static let cell: Float = 3
    static let wallHeight: Float = 3

    let width: Int
    let height: Int
    private let cells: [[Character]]

    private(set) var playerStart = GridPoint(col: 1, row: 1)
    private(set) var monsterStart = GridPoint(col: 1, row: 1)
    private(set) var exit = GridPoint(col: 0, row: 0)
    private(set) var keys: [GridPoint] = []
    private(set) var batteries: [GridPoint] = []
    private(set) var tables: [GridPoint] = []
    private(set) var walkable: [GridPoint] = []

    init(_ lines: [String]) {
        cells = lines.map { Array($0) }
        height = cells.count
        width = cells.first?.count ?? 0
        for row in 0..<height {
            for col in 0..<width {
                let p = GridPoint(col: col, row: row)
                switch cells[row][col] {
                case "P": playerStart = p
                case "M": monsterStart = p
                case "E": exit = p
                case "K": keys.append(p)
                case "B": batteries.append(p)
                case "T": tables.append(p)
                default: break
                }
                if !blocksMovement(p) { walkable.append(p) }
            }
        }
    }

    func character(at p: GridPoint) -> Character {
        guard p.row >= 0, p.row < height, p.col >= 0, p.col < width else { return "#" }
        return cells[p.row][p.col]
    }

    func isWall(_ p: GridPoint) -> Bool {
        let c = character(at: p)
        return c == "#" || c == "E"
    }

    func blocksMovement(_ p: GridPoint) -> Bool {
        isWall(p) || character(at: p) == "T"
    }

    func center(_ p: GridPoint, y: Float = 0) -> SCNVector3 {
        SCNVector3(Float(p.col) * HorrorMap.cell + HorrorMap.cell / 2, y,
                   Float(p.row) * HorrorMap.cell + HorrorMap.cell / 2)
    }

    func gridPoint(x: Float, z: Float) -> GridPoint {
        GridPoint(col: Int((x / HorrorMap.cell).rounded(.down)), row: Int((z / HorrorMap.cell).rounded(.down)))
    }

    /// The floor cell next to the front door, which the door faces into.
    var exitInside: GridPoint {
        let options = [GridPoint(col: exit.col - 1, row: exit.row), GridPoint(col: exit.col + 1, row: exit.row),
                       GridPoint(col: exit.col, row: exit.row - 1), GridPoint(col: exit.col, row: exit.row + 1)]
        return options.first { !blocksMovement($0) } ?? exit
    }

    // MARK: - Collision

    /// Pushes a circle at (x, z) out of any wall or table it overlaps.
    func resolve(x: Float, z: Float, radius: Float) -> (Float, Float) {
        var x = x, z = z
        let here = gridPoint(x: x, z: z)
        for _ in 0..<2 {
            for row in (here.row - 1)...(here.row + 1) {
                for col in (here.col - 1)...(here.col + 1) {
                    let p = GridPoint(col: col, row: row)
                    guard let box = obstacleBox(p) else { continue }
                    let nearestX = min(max(x, box.minX), box.maxX)
                    let nearestZ = min(max(z, box.minZ), box.maxZ)
                    let dx = x - nearestX, dz = z - nearestZ
                    let d2 = dx * dx + dz * dz
                    guard d2 < radius * radius else { continue }
                    if d2 > 0.000_001 {
                        let d = sqrt(d2)
                        x = nearestX + dx / d * radius
                        z = nearestZ + dz / d * radius
                    } else {
                        // Centre inside the box: push out along the shallowest side.
                        let pushes = [(box.minX - radius - x, Float(0)), (box.maxX + radius - x, Float(0)),
                                      (Float(0), box.minZ - radius - z), (Float(0), box.maxZ + radius - z)]
                        let best = pushes.min { abs($0.0) + abs($0.1) < abs($1.0) + abs($1.1) }!
                        x += best.0
                        z += best.1
                    }
                }
            }
        }
        return (x, z)
    }

    private func obstacleBox(_ p: GridPoint) -> (minX: Float, maxX: Float, minZ: Float, maxZ: Float)? {
        let c = HorrorMap.cell
        let x0 = Float(p.col) * c, z0 = Float(p.row) * c
        if isWall(p) { return (x0, x0 + c, z0, z0 + c) }
        if character(at: p) == "T" {
            let mid = center(p)
            return (mid.x - 1.05, mid.x + 1.05, mid.z - 0.65, mid.z + 0.65)
        }
        return nil
    }

    // MARK: - Sight and paths

    /// True if no wall stands between the two points (tables don't block sight).
    func hasLineOfSight(from a: SCNVector3, to b: SCNVector3) -> Bool {
        let dx = b.x - a.x, dz = b.z - a.z
        let steps = max(1, Int(sqrt(dx * dx + dz * dz) / 0.4))
        for i in 1..<steps {
            let t = Float(i) / Float(steps)
            if isWall(gridPoint(x: a.x + dx * t, z: a.z + dz * t)) { return false }
        }
        return true
    }

    /// Shortest walkable route (breadth-first), not including `start`.
    func path(from start: GridPoint, to goal: GridPoint) -> [GridPoint] {
        guard start != goal, !blocksMovement(goal) else { return [] }
        var cameFrom: [GridPoint: GridPoint] = [start: start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            if current == goal { break }
            for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let next = GridPoint(col: current.col + dc, row: current.row + dr)
                if cameFrom[next] == nil && !blocksMovement(next) {
                    cameFrom[next] = current
                    queue.append(next)
                }
            }
        }
        guard cameFrom[goal] != nil else { return [] }
        var route: [GridPoint] = []
        var step = goal
        while step != start {
            route.append(step)
            step = cameFrom[step]!
        }
        return route.reversed()
    }
}
