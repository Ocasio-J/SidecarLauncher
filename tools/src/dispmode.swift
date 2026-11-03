import CoreGraphics
import Foundation

let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: kCFBooleanTrue!] as CFDictionary

for id in onlineList() {
    let cur = CGDisplayCopyDisplayMode(id)
    print("display \(id) vendor=0x\(String(CGDisplayVendorNumber(id), radix: 16))")
    print("  NOW: \(cur?.width ?? 0)x\(cur?.height ?? 0) px=\(cur?.pixelWidth ?? 0)x\(cur?.pixelHeight ?? 0) \(cur?.refreshRate ?? 0)Hz")
    guard let modes = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] else { continue }
    var seen = Set<String>()
    for m in modes.sorted(by: { $0.width < $1.width }) {
        let key = "\(m.width)x\(m.height)/\(m.pixelWidth)x\(m.pixelHeight)"
        if seen.insert(key).inserted {
            let hidpi = m.pixelWidth != m.width ? "  <-- HiDPI" : ""
            print("  \(key) \(Int(m.refreshRate))Hz\(hidpi)")
        }
    }
}
