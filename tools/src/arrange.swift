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

func pixels(_ id: CGDirectDisplayID) -> Int32 {
    Int32(CGDisplayPixelsWide(id)) * Int32(CGDisplayPixelsHigh(id))
}

let ids = active()

guard let sidecar = ids.first(where: { CGDisplayVendorNumber($0) == SIDECAR }) else {
    print("ERR: no active display with vendor 0x\(String(SIDECAR, radix: 16)) (Sidecar)")
    exit(2)
}

let virtuals = ids.filter { CGDisplayVendorNumber($0) == VIRTUAL }
guard let vdisp = virtuals.max(by: { pixels($0) < pixels($1) }) else {
    print("ERR: no active display with vendor 0x\(String(VIRTUAL, radix: 16)) (virtual display)")
    exit(2)
}

print("sidecar \(sidecar) (vendor \(vendor(sidecar))), virtual \(vdisp) (vendor \(vendor(vdisp)))")

// A mirrored display cannot be configured, so clear any mirror on the Sidecar first.
print("phase 1: clear the mirror on the Sidecar")
if CGDisplayIsInMirrorSet(sidecar) != 0 {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success, let c = cfg else {
        print("  ERR: CGBeginDisplayConfiguration failed")
        exit(1)
    }
    let r = CGConfigureDisplayMirrorOfDisplay(c, sidecar, kCGNullDirectDisplay)
    let done = CGCompleteDisplayConfiguration(c, .permanently)
    print("  unmirror \(sidecar) rc=\(r.rawValue) commit=\(done.rawValue)")
    if done != .success {
        print("  ERR: CGCompleteDisplayConfiguration failed")
        exit(1)
    }
} else {
    print("  sidecar \(sidecar) is not in a mirror set, nothing to undo")
}

// The virtual display becomes the main one (0,0): Universal Control lasts longer when it
// is main and Sidecar mirrors it than the other way round.
print("phase 2: virtual display \(vdisp) to (0,0), the others to its right")
var cfg2: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&cfg2) == .success, let c2 = cfg2 else {
    print("  ERR: CGBeginDisplayConfiguration failed")
    exit(1)
}
let r0 = CGConfigureDisplayOrigin(c2, vdisp, 0, 0)
print("  \(label(vdisp)) \(vdisp) (vendor \(vendor(vdisp))) -> (0,0) rc=\(r0.rawValue)")
var x = Int32(CGDisplayPixelsWide(vdisp))

let others = ids.filter { $0 != vdisp }.sorted { a, b in
    let ab = CGDisplayIsBuiltin(a) != 0, bb = CGDisplayIsBuiltin(b) != 0
    if ab != bb { return ab }
    return a < b
}

for id in others {
    let left = x
    let r = CGConfigureDisplayOrigin(c2, id, left, 0)
    print("  \(label(id)) \(id) (vendor \(vendor(id))) -> (\(left),0) rc=\(r.rawValue)")
    x += Int32(CGDisplayPixelsWide(id))
}
let done2 = CGCompleteDisplayConfiguration(c2, .permanently)
print("  commit=\(done2.rawValue)")
if done2 != .success {
    print("  ERR: CGCompleteDisplayConfiguration failed")
    exit(1)
}

print("phase 3: mirror the Sidecar \(sidecar) onto the virtual display \(vdisp)")
var cfg3: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&cfg3) == .success, let c3 = cfg3 else {
    print("  ERR: CGBeginDisplayConfiguration failed")
    exit(1)
}
let r3 = CGConfigureDisplayMirrorOfDisplay(c3, sidecar, vdisp)
let done3 = CGCompleteDisplayConfiguration(c3, .permanently)
print("  mirror \(sidecar) -> \(vdisp) rc=\(r3.rawValue) commit=\(done3.rawValue)")
if done3 != .success {
    print("  ERR: CGCompleteDisplayConfiguration failed")
    exit(1)
}

print("phase 4: verify")
let isMain = CGDisplayIsMain(vdisp) != 0
let inSet = CGDisplayIsInMirrorSet(sidecar) != 0
let mirrorOf = CGDisplayMirrorsDisplay(sidecar)
print("  virtual \(vdisp) main=\(isMain)")
print("  sidecar \(sidecar) in_mirror_set=\(inSet) mirror_of=\(mirrorOf)")

if isMain && inSet && mirrorOf == vdisp {
    print("result: virtual display \(vdisp) is main, Sidecar \(sidecar) mirrors it")
} else {
    print("result: arrangement applied but the check is not clean (main=\(isMain) in_mirror_set=\(inSet) mirror_of=\(mirrorOf))")
}
exit(0)
