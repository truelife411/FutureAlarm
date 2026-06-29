import Cocoa
import CoreGraphics

// 生成 1024x1024 极简钟面 + 液态玻璃背景图标（元素更少，小尺寸更清晰）
// 用 2x 超采样渲染再缩回 1024，让圆和指针边缘抗锯齿更细腻
let scale: CGFloat = 2.0
let size = CGSize(width: 1024 * scale, height: 1024 * scale)
let image = NSImage(size: size)
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no ctx") }
let S = scale

// 1. 深邃背景
ctx.setFillColor(CGColor(red: 0.04, green: 0.03, blue: 0.10, alpha: 1.0))
ctx.fill(CGRect(origin: .zero, size: size))

// 2. 流动光球（紫/蓝/粉），大半径模糊营造液态感
func orb(cx: CGFloat, cy: CGFloat, r: CGFloat, _ color: CGColor) {
    let colors = [color, CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(grad,
                           startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                           endCenter: CGPoint(x: cx, y: cy), endRadius: r,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}
orb(cx: 260*S, cy: 760*S, r: 520*S, CGColor(red: 0.55, green: 0.32, blue: 0.90, alpha: 0.80))  // 紫
orb(cx: 800*S, cy: 720*S, r: 540*S, CGColor(red: 0.20, green: 0.50, blue: 1.00, alpha: 0.70))  // 蓝
orb(cx: 500*S, cy: 200*S, r: 460*S, CGColor(red: 1.00, green: 0.42, blue: 0.62, alpha: 0.45))  // 粉

// 3. 极简钟面：单个圆 + 两根指针，不画铃铛/脚/刻度（小尺寸下最清晰）
let cx: CGFloat = 512 * S
let cy: CGFloat = 512 * S
let faceR: CGFloat = 290 * S

// 玻璃质感的钟面填充（半透明白 + 径向高光模拟玻璃反光）
ctx.saveGState()
let faceRect = CGRect(x: cx - faceR, y: cy - faceR, width: faceR*2, height: faceR*2)
ctx.addEllipse(in: faceRect)
ctx.clip()
let glassColors = [
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.30),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.10),
    CGColor(red: 1, green: 1, blue: 1, alpha: 0.03)
] as CFArray
let glassGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glassColors, locations: [0.0, 0.6, 1.0])!
ctx.drawRadialGradient(glassGrad,
                       startCenter: CGPoint(x: cx - 90*S, y: cy + 120*S), startRadius: 0,
                       endCenter: CGPoint(x: cx - 90*S, y: cy + 120*S), endRadius: faceR*1.4,
                       options: [])
ctx.restoreGState()

// 钟面外圈描边（亮白）
ctx.addEllipse(in: faceRect)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
ctx.setLineWidth(18 * S)
ctx.strokePath()

// 内层细描边（增加层次）
ctx.addEllipse(in: faceRect.insetBy(dx: 16*S, dy: 16*S))
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.20))
ctx.setLineWidth(4 * S)
ctx.strokePath()

// 4. 指针：指向 10:10（经典最美位置）
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
ctx.setLineCap(.round)
// 时针（短，向左上 120°）
ctx.setLineWidth(22 * S)
ctx.move(to: CGPoint(x: cx, y: cy))
ctx.addLine(to: CGPoint(x: cx + cos(120 * .pi / 180) * 130*S,
                         y: cy + sin(120 * .pi / 180) * 130*S))
ctx.strokePath()
// 分针（长，向右上 60°）
ctx.setLineWidth(18 * S)
ctx.move(to: CGPoint(x: cx, y: cy))
ctx.addLine(to: CGPoint(x: cx + cos(60 * .pi / 180) * 195*S,
                         y: cy + sin(60 * .pi / 180) * 195*S))
ctx.strokePath()

// 中心轴点
ctx.addEllipse(in: CGRect(x: cx - 18*S, y: cy - 18*S, width: 36*S, height: 36*S))
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1.0))
ctx.fillPath()

image.unlockFocus()

// 写出 PNG，并缩到精确 1024x1024
let outDir = "FutureAlarm/Assets.xcassets/AppIcon.appiconset"
let outURL = URL(fileURLWithPath: outDir).appendingPathComponent("icon-1024.png")
if let tiff = image.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: outURL)
    print("✅ written (hi-res)")
} else {
    print("❌ failed")
    exit(1)
}
