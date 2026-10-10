import UIKit

/// Grimy surfaces drawn in code, so the game ships with no image files.
enum HorrorTextures {

    private static func draw(_ size: CGSize, _ body: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { body($0.cgContext) }
    }

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        UIColor(red: r, green: g, blue: b, alpha: a).cgColor
    }

    /// Speckle of tiny dark and light dots, the cheap trick that stops a
    /// surface looking like flat plastic.
    private static func grain(_ ctx: CGContext, _ size: CGSize, count: Int, strength: CGFloat) {
        for _ in 0..<count {
            let dark = Bool.random()
            ctx.setFillColor(dark ? color(0, 0, 0, strength) : color(1, 1, 1, strength * 0.5))
            let s = CGFloat.random(in: 1...3)
            ctx.fill(CGRect(x: .random(in: 0..<size.width), y: .random(in: 0..<size.height), width: s, height: s))
        }
    }

    private static func stains(_ ctx: CGContext, _ size: CGSize, count: Int, tint: (CGFloat, CGFloat, CGFloat)) {
        let space = CGColorSpaceCreateDeviceRGB()
        for _ in 0..<count {
            let center = CGPoint(x: .random(in: 0..<size.width), y: .random(in: 0..<size.height))
            let radius = CGFloat.random(in: size.width * 0.05...size.width * 0.3)
            let colors = [color(tint.0, tint.1, tint.2, .random(in: 0.15...0.4)), color(tint.0, tint.1, tint.2, 0)] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: radius, options: [])
            }
        }
    }

    /// Faded, stained striped wallpaper with grime collecting near the floor.
    static func wallpaper() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return draw(size) { ctx in
            ctx.setFillColor(color(0.36, 0.37, 0.29))
            ctx.fill(CGRect(origin: .zero, size: size))
            for i in 0..<8 {
                ctx.setFillColor(color(0.30, 0.31, 0.24, i % 2 == 0 ? 0.9 : 0.4))
                ctx.fill(CGRect(x: CGFloat(i) * 32 + 4, y: 0, width: 10, height: 256))
            }
            ctx.setFillColor(color(0.45, 0.44, 0.34, 0.6))
            for row in 0..<8 {
                for col in 0..<4 {
                    let x = CGFloat(col) * 64 + (row % 2 == 0 ? 20 : 52)
                    ctx.fillEllipse(in: CGRect(x: x, y: CGFloat(row) * 32 + 10, width: 9, height: 12))
                }
            }
            stains(ctx, size, count: 7, tint: (0.18, 0.14, 0.07))
            // Water streaks running down from the ceiling.
            for _ in 0..<4 {
                let x = CGFloat.random(in: 0..<256)
                ctx.setFillColor(color(0.15, 0.12, 0.06, 0.25))
                ctx.fill(CGRect(x: x, y: 0, width: .random(in: 2...6), height: .random(in: 60...200)))
            }
            let space = CGColorSpaceCreateDeviceRGB()
            if let grime = CGGradient(colorsSpace: space, colors: [color(0.05, 0.04, 0.02, 0), color(0.05, 0.04, 0.02, 0.75)] as CFArray,
                                      locations: [0, 1]) {
                ctx.drawLinearGradient(grime, start: CGPoint(x: 0, y: 170), end: CGPoint(x: 0, y: 256), options: [])
            }
            grain(ctx, size, count: 2500, strength: 0.18)
        }
    }

    /// Old, scuffed floorboards.
    static func floorboards() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return draw(size) { ctx in
            let plank: CGFloat = 256 / 6
            for i in 0..<6 {
                let shade = CGFloat.random(in: 0.75...1.0)
                ctx.setFillColor(color(0.27 * shade, 0.18 * shade, 0.11 * shade))
                let y = CGFloat(i) * plank
                ctx.fill(CGRect(x: 0, y: y, width: 256, height: plank))
                ctx.setStrokeColor(color(0.12, 0.08, 0.04, 0.5))
                ctx.setLineWidth(1)
                for _ in 0..<5 {
                    let gy = y + .random(in: 3...(plank - 3))
                    ctx.move(to: CGPoint(x: 0, y: gy))
                    ctx.addCurve(to: CGPoint(x: 256, y: gy + .random(in: -3...3)),
                                 control1: CGPoint(x: 85, y: gy + .random(in: -4...4)),
                                 control2: CGPoint(x: 170, y: gy + .random(in: -4...4)))
                    ctx.strokePath()
                }
                ctx.setFillColor(color(0.03, 0.02, 0.01))
                ctx.fill(CGRect(x: 0, y: y, width: 256, height: 2))
                let seam = CGFloat.random(in: 40...216)
                ctx.fill(CGRect(x: seam, y: y, width: 2, height: plank))
            }
            stains(ctx, size, count: 5, tint: (0.05, 0.03, 0.02))
            grain(ctx, size, count: 2000, strength: 0.2)
        }
    }

    static func ceiling() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return draw(size) { ctx in
            ctx.setFillColor(color(0.30, 0.29, 0.26))
            ctx.fill(CGRect(origin: .zero, size: size))
            stains(ctx, size, count: 6, tint: (0.20, 0.15, 0.08))
            grain(ctx, size, count: 3000, strength: 0.15)
        }
    }

    static func darkWood() -> UIImage {
        let size = CGSize(width: 128, height: 256)
        return draw(size) { ctx in
            ctx.setFillColor(color(0.16, 0.10, 0.06))
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.setStrokeColor(color(0.06, 0.04, 0.02, 0.6))
            for i in 0..<20 {
                let x = CGFloat(i) * 6.4 + .random(in: -1...1)
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x + .random(in: -3...3), y: 256))
                ctx.strokePath()
            }
            ctx.setFillColor(color(0.02, 0.01, 0.0))
            ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 3))
            ctx.fill(CGRect(x: 0, y: 125, width: 128, height: 3))
            grain(ctx, size, count: 800, strength: 0.2)
        }
    }

    /// A dim old portrait whose face has been scratched away.
    static func portrait() -> UIImage {
        let size = CGSize(width: 128, height: 160)
        return draw(size) { ctx in
            ctx.setFillColor(color(0.10, 0.08, 0.05))
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.setFillColor(color(0.22, 0.20, 0.16))
            ctx.fillEllipse(in: CGRect(x: 38, y: 30, width: 52, height: 66))
            ctx.fill(CGRect(x: 22, y: 100, width: 84, height: 60))
            ctx.setFillColor(color(0.02, 0.02, 0.02))
            ctx.fillEllipse(in: CGRect(x: 48, y: 52, width: 11, height: 9))
            ctx.fillEllipse(in: CGRect(x: 69, y: 52, width: 11, height: 9))
            ctx.setStrokeColor(color(0.05, 0.04, 0.03, 0.9))
            ctx.setLineWidth(2)
            for _ in 0..<14 {
                let y = CGFloat.random(in: 40...90)
                ctx.move(to: CGPoint(x: .random(in: 36...60), y: y))
                ctx.addLine(to: CGPoint(x: .random(in: 66...92), y: y + .random(in: -8...8)))
                ctx.strokePath()
            }
            grain(ctx, size, count: 900, strength: 0.25)
        }
    }

    /// Dark edges around the screen, like an old camera lens.
    static func vignette(size: CGSize, tint: UIColor = .black) -> UIImage {
        draw(size) { ctx in
            let space = CGColorSpaceCreateDeviceRGB()
            let colors = [tint.withAlphaComponent(0).cgColor, tint.withAlphaComponent(0.85).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0.45, 1]) else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                   endRadius: hypot(size.width, size.height) / 2, options: [.drawsAfterEndLocation])
        }
    }
}
