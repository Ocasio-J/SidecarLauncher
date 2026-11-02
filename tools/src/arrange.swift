import CoreGraphics
import Foundation

let SIDECAR: UInt32 = 0x6161706c
let VIRTUAL: UInt32 = 0x5644

func active() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    CGGetActiveDisplayList(n, &ids, &n)
    return Array(ids.prefix(Int(n)))
}

func vendor(_ id: CGDirectDisplayID) -> String {
    "0x" + String(CGDisplayVendorNumber(id), radix: 16)
}

func label(_ id: CGDirectDisplayID) -> String {
    let v = CGDisplayVendorNumber(id)
    if v == SIDECAR { return "sidecar" }
    if v == VIRTUAL { return "virtual" }
    if CGDisplayIsBuiltin(id) != 0 { return "builtin" }
    return "display"
}

let ids = active()
guard let sidecar = ids.first(where: { CGDisplayVendorNumber($0) == SIDECAR }) else {
    print("ERR: no active display with vendor 0x\(String(SIDECAR, radix: 16)) (Sidecar)")
    exit(2)
}

if ids.count == 1 {
    let b = CGDisplayBounds(sidecar)
    print("only one display (\(sidecar)): nothing to arrange")
    print("origin \(sidecar) = (\(Int(b.origin.x)),\(Int(b.origin.y))) \(Int(b.width))x\(Int(b.height))")
    exit(0)
}

var cfg: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&cfg) == .success, let c = cfg else {
    print("ERR: CGBeginDisplayConfiguration failed")
    exit(1)
}

var x: Int32 = 0
var placed: [CGDirectDisplayID] = [sidecar]

let r0 = CGConfigureDisplayOrigin(c, sidecar, 0, 0)
print("\(label(sidecar)) \(sidecar) (vendor \(vendor(sidecar))) -> (0,0) rc=\(r0.rawValue)")
x = Int32(CGDisplayPixelsWide(sidecar))

let others = ids.filter { $0 != sidecar }.sorted { a, b in
    let ab = CGDisplayIsBuiltin(a) != 0, bb = CGDisplayIsBuiltin(b) != 0
    if ab != bb { return ab }
    return a < b
}

for id in others {
    let left = x
    let r = CGConfigureDisplayOrigin(c, id, left, 0)
    print("\(label(id)) \(id) (vendor \(vendor(id))) -> (\(left),0) rc=\(r.rawValue)")
    x += Int32(CGDisplayPixelsWide(id))
    placed.append(id)
}

let done = CGCompleteDisplayConfiguration(c, .permanently)
print("commit = \(done.rawValue)")
if done != .success {
    print("ERR: CGCompleteDisplayConfiguration failed")
    exit(1)
}

for id in placed {
    let b = CGDisplayBounds(id)
    print("origin \(id) = (\(Int(b.origin.x)),\(Int(b.origin.y))) \(Int(b.width))x\(Int(b.height))")
}

print("result: sidecar \(sidecar) at (0,0), \(others.count) other display(s) to the right")
exit(0)
