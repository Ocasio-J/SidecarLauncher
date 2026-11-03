import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1 else { print("usage: setmode <WxH>"); exit(1) }
let parts = CommandLine.arguments[1].lowercased().split(separator: "x")
guard parts.count == 2, let W = Int(parts[0]), let H = Int(parts[1]) else {
    print("invalid format, expected e.g. 1165x809"); exit(1)
}

guard let id = selectSidecar(onlineList()) else {
    print("ERR: no online Sidecar display"); exit(1)
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
