import AppKit

// 生成 1024x1024 应用图标：深色圆角底 + 居中灵动岛
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.setShouldAntialias(true)

let full = NSRect(x: 0, y: 0, width: size, height: size)
let inset: CGFloat = 84
let body = full.insetBy(dx: inset, dy: inset)
let radius: CGFloat = 190

// 背景
let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.18, alpha: 1),
    NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.03, alpha: 1),
])
gradient?.draw(in: path, angle: -70)

NSColor.white.withAlphaComponent(0.10).setStroke()
path.lineWidth = 3
path.stroke()

// 岛体
let islandRect = NSRect(x: body.minX + 118, y: body.midY - 96, width: body.width - 236, height: 192)
let island = NSBezierPath(roundedRect: islandRect, xRadius: 96, yRadius: 96)

let shadow = NSShadow()
shadow.shadowColor = NSColor(calibratedRed: 0.30, green: 0.50, blue: 1.0, alpha: 0.55)
shadow.shadowBlurRadius = 60
shadow.shadowOffset = .zero
shadow.set()

NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
island.fill()

NSGraphicsContext.current?.saveGraphicsState()

// 岛内波形：五根竖条
let heights: [CGFloat] = [34, 62, 90, 58, 30]
let barWidth: CGFloat = 18
let gap: CGFloat = 20
let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = islandRect.midX - totalWidth / 2 + 26
for h in heights {
    let r = NSRect(x: x, y: islandRect.midY - h / 2, width: barWidth, height: h)
    NSColor(calibratedWhite: 0.07, alpha: 1).setFill()
    NSBezierPath(roundedRect: r, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
    x += barWidth + gap
}

// 未读红点
let dotRect = NSRect(x: islandRect.maxX - 62, y: islandRect.midY - 15, width: 30, height: 30)
NSColor(calibratedRed: 1.0, green: 0.32, blue: 0.30, alpha: 1).setFill()
NSBezierPath(ovalIn: dotRect).fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("icon render failed")
    exit(1)
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
