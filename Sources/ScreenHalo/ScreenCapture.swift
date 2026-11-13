import CoreMedia
import HaloCore
import ScreenCaptureKit

final class FrameReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let layout: EdgeLayout
    let depth: Double
    let onFrame: @Sendable ([RGB]) -> Void
    let onError: @Sendable (String) -> Void
    private var sampler: EdgeSampler?
    private var lastColors: [RGB] = []
    private var lastGeometry: [CGFloat] = []

    init(
        layout: EdgeLayout, depth: Double = 0.20, onFrame: @escaping @Sendable ([RGB]) -> Void,
        onError: @escaping @Sendable (String) -> Void
    ) {
        self.layout = layout
        self.depth = depth
        self.onFrame = onFrame
        self.onError = onError
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError("Screen capture stopped: \(error.localizedDescription)")
    }

    func stream(
        _ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen else { return }
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let info = attachments.first,
            let status = info[.status] as? Int
        else {
            lastColors = []
            return
        }
        guard status == SCFrameStatus.complete.rawValue else {
            if status != SCFrameStatus.idle.rawValue { lastColors = [] }
            return
        }
        guard let image = CMSampleBufferGetImageBuffer(buffer) else {
            lastColors = []
            return
        }
        let width = CVPixelBufferGetWidth(image)
        let height = CVPixelBufferGetHeight(image)
        if sampler?.width != width || sampler?.height != height {
            sampler = EdgeSampler(width: width, height: height, layout: layout, depth: depth)
            lastColors = []
        }
        guard let sampler else { return }
        var dirty: [CGRect]?
        if let rect = info[.contentRect] as? CGRect,
            let scale = info[.contentScale] as? CGFloat,
            let factor = info[.scaleFactor] as? CGFloat,
            rect.width > 0, rect.height > 0, scale > 0, factor > 0,
            [rect.minX, rect.minY, rect.width, rect.height, scale, factor].allSatisfy({ $0.isFinite })
        {
            let geometry = [rect.minX, rect.minY, rect.width, rect.height, scale, factor]
            if geometry == lastGeometry, let values = info[.dirtyRects] as? [NSValue] {
                dirty = values.map { $0.rectValue }
            }
            lastGeometry = geometry
        } else {
            lastGeometry = []
        }
        let affected = sampler.affectedLEDs(dirtyRects: lastColors.isEmpty ? nil : dirty)
        guard !affected.isEmpty else { return }
        guard CVPixelBufferLockBaseAddress(image, .readOnly) == kCVReturnSuccess else {
            lastColors = []
            return
        }
        defer { CVPixelBufferUnlockBaseAddress(image, .readOnly) }
        guard let address = CVPixelBufferGetBaseAddress(image) else {
            lastColors = []
            return
        }
        let rowBytes = CVPixelBufferGetBytesPerRow(image)
        let colors = sampler.averageBGRA(
            UnsafeRawBufferPointer(start: address, count: rowBytes * height), rowBytes: rowBytes,
            previous: lastColors, updating: affected)
        if !colors.isEmpty && colors != lastColors {
            lastColors = colors
            onFrame(colors)
        }
    }
}

@MainActor
final class ScreenCapture {
    private var stream: SCStream?
    private let receiver: FrameReceiver
    private let frameRate: Int

    init(receiver: FrameReceiver, frameRate: Int = 40) {
        self.receiver = receiver
        self.frameRate = frameRate
    }

    func start(displayID: CGDirectDisplayID) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw NSError(
                domain: "ScreenHalo", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The selected display is disconnected."])
        }
        try Task.checkCancellation()
        let config = SCStreamConfiguration()
        let size = display.frame.size
        config.sourceRect = CGRect(origin: .zero, size: size)
        let scale = 160 / max(size.width, size.height)
        config.width = max(1, Int((size.width * scale).rounded()))
        config.height = max(1, Int((size.height * scale).rounded()))
        config.scalesToFit = true
        config.preservesAspectRatio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        config.capturesAudio = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(frameRate))
        config.queueDepth = 3
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: config, delegate: receiver)
        try stream.addStreamOutput(
            receiver, type: .screen,
            sampleHandlerQueue: DispatchQueue(label: "ScreenHalo.edges", qos: .utility))
        self.stream = stream
        do {
            try await stream.startCapture()
            try Task.checkCancellation()
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        let oldStream = stream
        stream = nil
        try? await oldStream?.stopCapture()
    }
}
