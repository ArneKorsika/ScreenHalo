import CoreGraphics
import Foundation

public struct EdgeLayout: Equatable, Sendable {
    public let left: Int
    public let top: Int
    public let right: Int
    public var count: Int { left + top + right }

    public init(left: Int, top: Int, right: Int) {
        self.left = left
        self.top = top
        self.right = right
    }
}

public struct EdgeSampler: Sendable {
    private struct Region: Sendable {
        let x: Range<Int>
        let y: Range<Int>
    }
    private let regions: [Region]
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int, layout: EdgeLayout, depth: Double = 0.20) {
        self.width = width
        self.height = height
        guard width > 0, height > 0, layout.left >= 0, layout.top >= 0, layout.right >= 0,
            (1...255).contains(layout.count)
        else {
            regions = []
            return
        }
        let sideDepth = max(1, Int((Double(width) * max(0.02, min(0.30, depth))).rounded()))
        let topDepth = max(1, Int((Double(height) * max(0.02, min(0.30, depth))).rounded()))
        var boxes: [Region] = []
        for led in 0..<layout.left {
            let index = layout.left - 1 - led
            let start = index * height / layout.left
            let end = (index + 1) * height / layout.left
            boxes.append(Region(x: 0..<min(width, sideDepth), y: start..<max(start + 1, end)))
        }
        for led in 0..<layout.top {
            let start = led * width / layout.top
            let end = (led + 1) * width / layout.top
            boxes.append(Region(x: start..<max(start + 1, end), y: 0..<min(height, topDepth)))
        }
        for led in 0..<layout.right {
            let start = led * height / layout.right
            let end = (led + 1) * height / layout.right
            boxes.append(Region(x: max(0, width - sideDepth)..<width, y: start..<max(start + 1, end)))
        }
        regions = boxes
    }

    public func affectedLEDs(dirtyRects: [CGRect]?) -> [Int] {
        guard let dirtyRects else { return Array(regions.indices) }
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        guard
            dirtyRects.allSatisfy({ rect in
                !rect.isNull && !rect.isInfinite && rect.origin.x.isFinite && rect.origin.y.isFinite
                    && rect.width.isFinite && rect.height.isFinite && rect.size.width >= 0
                    && rect.size.height >= 0
                    && rect.minX >= 0 && rect.minY >= 0 && rect.maxX <= bounds.maxX
                    && rect.maxY <= bounds.maxY
            })
        else { return Array(regions.indices) }
        let damage = dirtyRects.filter { !$0.isEmpty }.map { $0.insetBy(dx: -1, dy: -1) }
        return regions.indices.filter { led in
            let region = regions[led]
            let box = CGRect(
                x: region.x.lowerBound, y: region.y.lowerBound,
                width: region.x.count, height: region.y.count)
            return damage.contains { $0.intersects(box) }
        }
    }

    public func averageBGRA(
        _ bytes: UnsafeRawBufferPointer, rowBytes: Int,
        previous: [RGB] = [], updating indices: [Int]? = nil
    ) -> [RGB] {
        guard !regions.isEmpty, rowBytes >= width * 4, bytes.count >= rowBytes * height else { return [] }
        let reuse = previous.count == regions.count
        let affected = reuse ? (indices ?? Array(regions.indices)) : Array(regions.indices)
        guard affected.allSatisfy({ regions.indices.contains($0) }) else { return [] }
        var colors = reuse ? previous : Array(repeating: RGB.black, count: regions.count)
        for led in affected {
            let region = regions[led]
            var r = 0
            var g = 0
            var b = 0
            for y in region.y {
                for x in region.x {
                    let offset = y * rowBytes + x * 4
                    b += Int(bytes[offset])
                    g += Int(bytes[offset + 1])
                    r += Int(bytes[offset + 2])
                }
            }
            let count = region.x.count * region.y.count
            colors[led] = RGB(UInt8(r / count), UInt8(g / count), UInt8(b / count))
        }
        return colors
    }
}
