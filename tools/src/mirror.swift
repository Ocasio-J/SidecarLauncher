import CoreGraphics
import Foundation

let ids = onlineList()
guard let s = selectSidecar(ids),
      let b = ids.first(where: { CGDisplayIsBuiltin($0) != 0 }) else {
    print("ERR: two displays needed (found: \(ids))"); exit(1)
}
var cfg: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&cfg) == .success, let c = cfg else { print("ERR: begin failed"); exit(1) }
let r = CGConfigureDisplayMirrorOfDisplay(c, s, b)
let done = CGCompleteDisplayConfiguration(c, .permanently)
print("mirror sidecar(\(s)) -> builtin(\(b)) = \(r.rawValue), commit = \(done.rawValue)")
