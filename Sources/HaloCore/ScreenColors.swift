import Foundation

public struct RGB: Equatable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }
    public static let black = RGB(0, 0, 0)
}

public enum ScreenColors {
    private static let linearIntensity = (0...255).map { pow(Double($0) / 255, 2.2) * 255 }

    public static func output(_ colors: [RGB], brightness: Double, reversed: Bool) -> [RGB] {
        let gain = max(0, min(1, brightness))
        func channel(_ value: UInt8) -> UInt8 {
            UInt8((linearIntensity[Int(value)] * gain).rounded())
        }
        let result = colors.map { RGB(channel($0.r), channel($0.g), channel($0.b)) }
        return reversed ? Array(result.reversed()) : result
    }
}

public struct ColorSmoother {
    private var channels: [Double] = []
    public private(set) var isSettled = false
    public init() {}
    public mutating func update(_ colors: [RGB], smoothing: Double = 0.5) -> [RGB] {
        if channels.count != colors.count * 3 {
            channels = Array(repeating: 0, count: colors.count * 3)
        }
        let alpha = max(0.05, min(1, 1 - smoothing))
        var settled = true
        func advance(_ current: inout Double, to target: Double) {
            current += alpha * (target - current)
            if abs(target - current) < 0.5 { current = target } else { settled = false }
        }
        let result = colors.enumerated().map { index, color in
            let offset = index * 3
            advance(&channels[offset], to: Double(color.r))
            advance(&channels[offset + 1], to: Double(color.g))
            advance(&channels[offset + 2], to: Double(color.b))
            return RGB(
                UInt8(channels[offset].rounded()),
                UInt8(channels[offset + 1].rounded()), UInt8(channels[offset + 2].rounded()))
        }
        isSettled = settled
        return result
    }
}

public struct ColorRenderer {
    private var smoother = ColorSmoother()
    private var target: [RGB] = []
    private var brightness: Double?
    private var smoothing: Double?
    private var reversed = false
    public private(set) var output: [RGB] = []
    public var isSettled: Bool { smoother.isSettled }

    public init() {}

    public mutating func update(_ colors: [RGB], brightness: Double, reversed: Bool, smoothing: Double = 0.5)
        -> [RGB]?
    {
        guard
            colors != target || self.brightness != brightness || self.reversed != reversed
                || self.smoothing != smoothing || !isSettled
        else { return nil }
        target = colors
        self.brightness = brightness
        self.smoothing = smoothing
        self.reversed = reversed
        let next = ScreenColors.output(
            smoother.update(colors, smoothing: smoothing), brightness: brightness, reversed: reversed)
        guard next != output else { return nil }
        output = next
        return next
    }
}

public enum Skydimo {
    public static func packet(_ colors: [RGB]) -> [UInt8]? {
        guard (1...255).contains(colors.count) else { return nil }
        return [0x41, 0x64, 0x61, 0, 0, UInt8(colors.count)]
            + colors.flatMap { [$0.r, $0.g, $0.b] }
    }
}
