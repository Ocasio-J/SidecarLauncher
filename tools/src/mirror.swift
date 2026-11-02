import CoreGraphics
import Foundation

func active() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    CGGetActiveDisplayList(n, &ids, &n)
    return Array(ids.prefix(Int(n)))
}
// known vendors: 0x6161706c = Sidecar/AirPlay display, 0x756e6b6e = headless framebuffer
func isSidecar(_ id: CGDirectDisplayID) -> Bool {
    let v = CGDisplayVendorNumber(id), m = CGDisplayModelNumber(id)
    return v == 0x6161706c || v == 0x756e6b6e || m == 0x69506164
}

let ids = active()
guard let s = ids.first(where: { isSidecar($0) && CGDisplayIsBuiltin($0) == 0 }),
      let b = ids.first(where: { CGDisplayIsBuiltin($0) != 0 }) else {
    print("ERR: two displays needed (found: \(ids))"); exit(1)
}
var cfg: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&cfg) == .success, let c = cfg else { print("ERR: begin failed"); exit(1) }
let r = CGConfigureDisplayMirrorOfDisplay(c, s, b)
let done = CGCompleteDisplayConfiguration(c, .permanently)
print("mirror sidecar(\(s)) -> builtin(\(b)) = \(r.rawValue), commit = \(done.rawValue)")
