import CoreGraphics

let sidecarVendor: UInt32 = 0x6161706c
let virtualVendor: UInt32 = 0x5644

func onlineList() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    CGGetOnlineDisplayList(n, &ids, &n)
    return Array(ids.prefix(Int(n)))
}

func displayPixels(_ id: CGDirectDisplayID) -> Int32 {
    Int32(CGDisplayPixelsWide(id)) * Int32(CGDisplayPixelsHigh(id))
}

func selectSidecar(_ ids: [CGDirectDisplayID]) -> CGDirectDisplayID? {
    let candidates = ids.filter { CGDisplayVendorNumber($0) == sidecarVendor }
    guard !candidates.isEmpty else { return nil }
    let preferred = candidates.filter { CGDisplayIsActive($0) != 0 || CGDisplayMirrorsDisplay($0) != 0 }
    return (preferred.isEmpty ? candidates : preferred).max()
}

func selectVirtual(_ ids: [CGDirectDisplayID]) -> CGDirectDisplayID? {
    let candidates = ids.filter { CGDisplayVendorNumber($0) == virtualVendor }
    guard !candidates.isEmpty else { return nil }
    if let id = candidates.filter({ CGDisplayIsMain($0) != 0 }).max() { return id }
    if let id = candidates.filter({ CGDisplayIsActive($0) != 0 }).max() { return id }
    return candidates.max { displayPixels($0) < displayPixels($1) }
}
