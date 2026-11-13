import AppKit

struct DisplayChoice: Identifiable {
    let id: String
    let displayID: CGDirectDisplayID
    let name: String

    static func connected() -> [DisplayChoice] {
        let screens = NSScreen.screens.sorted {
            if $0.frame.minX != $1.frame.minX { return $0.frame.minX < $1.frame.minX }
            return $0.frame.minY > $1.frame.minY
        }
        return screens.enumerated().compactMap { index, screen in
            guard
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
            else { return nil }
            let position: String
            if screens.count == 1 {
                position = "Only display"
            } else if index == 0 {
                position = "Leftmost"
            } else if index == screens.count - 1 {
                position = "Rightmost"
            } else {
                position = "Middle"
            }
            let identity = CFUUIDCreateString(nil, uuid) as String
            return DisplayChoice(
                id: identity, displayID: number.uint32Value,
                name: "\(index + 1). \(screen.localizedName) — \(position)")
        }
    }
}
