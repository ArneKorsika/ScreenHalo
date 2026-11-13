import Darwin
import Foundation

public final class USBStrip: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ScreenHalo.usb")
    private let lock = NSLock()
    private var writing = false
    private var fd: Int32
    private var refreshTimer: DispatchSourceTimer?
    private var lastPacket: [UInt8] = []
    private var lastWriteTime: UInt64 = 0
    private let onFailure: @Sendable (String) -> Void

    public static func ports() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? [])
            .filter { $0.hasPrefix("cu.usbserial") || $0.hasPrefix("cu.wchusbserial") }
            .sorted().map { "/dev/" + $0 }
    }

    public init(path: String, onFailure: @escaping @Sendable (String) -> Void) throws {
        self.onFailure = onFailure
        fd = Darwin.open(path, O_WRONLY | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw Self.error("Cannot open USB strip") }
        do {
            guard ioctl(fd, TIOCEXCL) == 0 else { throw Self.error("USB strip is in use") }
            var options = termios()
            guard tcgetattr(fd, &options) == 0 else { throw Self.error("Cannot read serial settings") }
            cfmakeraw(&options)
            cfsetispeed(&options, speed_t(B115200))
            cfsetospeed(&options, speed_t(B115200))
            options.c_cflag =
                (options.c_cflag & ~tcflag_t(CSIZE | PARENB | CSTOPB | CRTSCTS))
                | tcflag_t(CS8 | CLOCAL | CREAD)
            guard tcsetattr(fd, TCSANOW, &options) == 0 else {
                throw Self.error("Cannot configure USB strip")
            }
        } catch {
            _ = ioctl(fd, TIOCNXCL)
            Darwin.close(fd)
            throw error
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(
            domain: "ScreenHalo.USB", code: Int(errno),
            userInfo: [NSLocalizedDescriptionKey: "\(message): \(String(cString: strerror(errno)))"])
    }

    @discardableResult
    public func send(_ colors: [RGB]) -> Bool {
        guard let packet = Skydimo.packet(colors) else { return false }
        lock.lock()
        guard !writing else {
            lock.unlock()
            return false
        }
        writing = true
        lock.unlock()
        queue.async {
            defer {
                self.lock.lock()
                self.writing = false
                self.lock.unlock()
            }
            guard self.fd >= 0 else { return }
            guard self.write(packet) else {
                self.handleWriteFailure()
                return
            }
            self.lastPacket = packet
            self.lastWriteTime = DispatchTime.now().uptimeNanoseconds
            self.startRefreshing()
        }
        return true
    }

    private func startRefreshing() {
        guard refreshTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .milliseconds(500), repeating: .milliseconds(500),
            leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            guard let self, self.fd >= 0, !self.lastPacket.isEmpty else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now - self.lastWriteTime >= 500_000_000 else { return }
            if self.write(self.lastPacket) {
                self.lastWriteTime = DispatchTime.now().uptimeNanoseconds
            } else {
                self.handleWriteFailure()
            }
        }
        refreshTimer = timer
        timer.resume()
    }

    private func stopRefreshing() {
        refreshTimer?.cancel()
        refreshTimer = nil
        lastPacket = []
    }

    private func handleWriteFailure() {
        stopRefreshing()
        guard fd >= 0 else { return }
        _ = ioctl(fd, TIOCNXCL)
        Darwin.close(fd)
        fd = -1
        onFailure("USB write failed. Check the cable and close other LED apps, then start again.")
    }

    private func write(_ packet: [UInt8]) -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + 150_000_000
        return packet.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                guard DispatchTime.now().uptimeNanoseconds < deadline else { return false }
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if n > 0 {
                    offset += n
                    continue
                }
                if n < 0 && errno == EINTR { continue }
                guard n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) else { return false }
                var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                guard Darwin.poll(&descriptor, 1, 20) >= 0 else { return false }
            }
            return true
        }
    }

    public func close(count: Int) async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.stopRefreshing()
                if self.fd >= 0 {
                    if let packet = Skydimo.packet(Array(repeating: .black, count: count)) {
                        _ = self.write(packet)
                    }
                    _ = ioctl(self.fd, TIOCNXCL)
                    Darwin.close(self.fd)
                    self.fd = -1
                }
                continuation.resume()
            }
        }
    }
}
