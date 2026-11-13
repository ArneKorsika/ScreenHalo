import AppKit
import SwiftUI

enum HaloStyle {
    static let background = Color(hex: 0x17191F)
    static let inset = Color(hex: 0x0F1116)
    static let sidebar = Color(hex: 0x121419)
    static let cyan = Color(hex: 0x3DD6F5)
    static let palette = [cyan, Color(hex: 0x8B5CF6), Color(hex: 0xF0529C), Color(hex: 0xFFB547)]
    static let spectrum = AngularGradient(
        colors: palette + [cyan], center: .center, startAngle: .degrees(210), endAngle: .degrees(570))

    @MainActor
    static func installApplicationIcon(bundle: Bundle = .main) {
        let size = NSSize(width: 512, height: 512)
        var proposed = NSRect(origin: .zero, size: size)
        var bitmap: CGImage?
        if let url = bundle.url(forResource: "ScreenHalo", withExtension: "icns"),
            let icon = NSImage(contentsOf: url)
        {
            bitmap = icon.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
        }
        if bitmap == nil {
            let renderer = ImageRenderer(content: HaloLogo().frame(width: 512, height: 512))
            renderer.scale = 2
            bitmap = renderer.cgImage
        }
        if let bitmap {
            NSApp.applicationIconImage = NSImage(cgImage: bitmap, size: size)
            NSApp.dockTile.display()
        }
    }

    static func menuIcon(active: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: true) { _ in
            let path = NSBezierPath()
            NSColor.labelColor.set()
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            if active {
                path.move(to: NSPoint(x: 4, y: 15))
                path.line(to: NSPoint(x: 4, y: 7))
                path.curve(
                    to: NSPoint(x: 7, y: 4), controlPoint1: NSPoint(x: 4, y: 5),
                    controlPoint2: NSPoint(x: 5, y: 4))
                path.line(to: NSPoint(x: 15, y: 4))
                path.curve(
                    to: NSPoint(x: 18, y: 7), controlPoint1: NSPoint(x: 17, y: 4),
                    controlPoint2: NSPoint(x: 18, y: 5))
                path.line(to: NSPoint(x: 18, y: 15))
                path.stroke()
            }
            let screen = NSBezierPath(
                roundedRect: NSRect(x: 7, y: 7, width: 8, height: 6), xRadius: 1, yRadius: 1)
            if active {
                screen.fill()
            } else {
                screen.lineWidth = 1.4
                screen.stroke()
            }
            let stand = NSBezierPath()
            stand.lineWidth = 1.5
            stand.lineCapStyle = .round
            stand.move(to: NSPoint(x: 11, y: 13))
            stand.line(to: NSPoint(x: 11, y: 17))
            stand.move(to: NSPoint(x: 8.5, y: 18))
            stand.line(to: NSPoint(x: 13.5, y: 18))
            stand.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 255) / 255,
            green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

struct HaloLogo: View {
    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: s * 0.225)
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: 0x1C1F28), Color(hex: 0x07080B)],
                            center: .init(x: 0.5, y: 0.38), startRadius: 0, endRadius: s * 0.7))
                RoundedRectangle(cornerRadius: s * 0.08)
                    .fill(HaloStyle.spectrum).frame(width: s * 0.7, height: s * 0.52)
                    .blur(radius: s * 0.074).offset(y: -s * 0.06)
                RoundedRectangle(cornerRadius: s * 0.037)
                    .fill(HaloStyle.spectrum).frame(width: s * 0.548, height: s * 0.378)
                    .offset(y: -s * 0.055)
                RoundedRectangle(cornerRadius: s * 0.03)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0x13151B), Color(hex: 0x08090C)], startPoint: .top,
                            endPoint: .bottom)
                    )
                    .frame(width: s * 0.52, height: s * 0.35).offset(y: -s * 0.055)
                Rectangle().fill(Color(hex: 0x0A0B0F)).frame(width: s * 0.08, height: s * 0.08).offset(
                    y: s * 0.174)
                Capsule().fill(Color(hex: 0x14161C)).frame(width: s * 0.26, height: s * 0.026).offset(
                    y: s * 0.223)
            }.clipShape(RoundedRectangle(cornerRadius: s * 0.225))
        }.accessibilityLabel("ScreenHalo")
    }
}
