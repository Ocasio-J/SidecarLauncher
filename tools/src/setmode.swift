import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1 else { print("usage: setmode <WxH>"); exit(1) }
let parts = CommandLine.arguments[1].lowercased().split(separator: "x")
guard parts.count == 2, let W = Int(parts[0]), let H = Int(parts[1]) else {
    print("invalid format, expected e.g. 1165x809"); exit(1)
}

var n: UInt32 = 0
CGGetActiveDisplayList(0, nil, &n)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(n)); CGGetActiveDisplayList(n, &ids, &n)
// Sidecar display: vendor 0x6161706c
guard let id = ids.prefix(Int(n)).first(where: { CGDisplayVendorNumber($0) == 0x6161706c }) else {
    print("ERR: no active Sidecar display"); exit(1)
}

let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: kCFBooleanTrue!] as CFDictionary
guard let all = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] else { print("ERR: cannot read modes"); exit(1) }
let candidates = all.filter { $0.width == W && $0.height == H }
guard let mode = candidates.first(where: { $0.pixelWidth > $0.width }) ?? candidates.first else {
    print("ERR: mode \(W)x\(H) not available"); exit(1)
}

var cfg: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&cfg) == .success, let c = cfg else { print("ERR: begin failed"); exit(1) }
let r = CGConfigureDisplayWithDisplayMode(c, id, mode, nil)
let done = CGCompleteDisplayConfiguration(c, .permanently)
print("display \(id) -> \(mode.width)x\(mode.height) px=\(mode.pixelWidth)x\(mode.pixelHeight) \(Int(mode.refreshRate))Hz  (set=\(r.rawValue) commit=\(done.rawValue))")
exit(done == .success ? 0 : 1)
