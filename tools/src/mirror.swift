import CoreGraphics
import Foundation

let ids = onlineList()
guard let s = selectSidecar(ids),
      let b = ids.first(where: { CGDisplayIsBuiltin($0) != 0 }) else {
    print("ERR: two displays needed (found: \(ids))"); exit(1)
}

if CGDisplayMirrorsDisplay(s) == b {
    print("already mirrored: sidecar \(s) -> builtin \(b)")
    exit(0)
}

var cfg: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&cfg) == .success, let c = cfg else { print("ERR: begin failed"); exit(1) }
let r = CGConfigureDisplayMirrorOfDisplay(c, s, b)
let done = CGCompleteDisplayConfiguration(c, .permanently)
print("mirror sidecar(\(s)) -> builtin(\(b)) = \(r.rawValue), commit = \(done.rawValue)")
if r != .success || done != .success {
    print("ERR: mirroring the Sidecar onto the built-in display failed (mirror=\(r.rawValue) commit=\(done.rawValue))")
    exit(1)
}
exit(0)
