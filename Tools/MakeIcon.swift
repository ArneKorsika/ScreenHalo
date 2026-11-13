import AppKit
import SwiftUI

@main
@MainActor
enum MakeIcon {
    static func main() throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let renderer = ImageRenderer(
                    content: HaloLogo().frame(width: CGFloat(points), height: CGFloat(points)))
                renderer.scale = CGFloat(scale)
                guard let image = renderer.cgImage,
                    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                else {
                    fatalError("Could not render ScreenHalo icon")
                }
                let suffix = scale == 2 ? "@2x" : ""
                try data.write(to: directory.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
            }
        }
    }
}
