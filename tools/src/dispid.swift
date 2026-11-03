import CoreGraphics
import Foundation
var c: UInt32 = 0; CGGetOnlineDisplayList(0, nil, &c)
var ids = [CGDirectDisplayID](repeating: 0, count: Int(c)); CGGetOnlineDisplayList(c, &ids, &c)
for id in ids.prefix(Int(c)) {
  print("id=\(id) vendor=0x\(String(CGDisplayVendorNumber(id), radix: 16)) model=0x\(String(CGDisplayModelNumber(id), radix: 16)) serial=\(CGDisplaySerialNumber(id)) builtin=\(CGDisplayIsBuiltin(id) != 0) main=\(CGDisplayIsMain(id) != 0) active=\(CGDisplayIsActive(id) != 0) mirror_of=\(CGDisplayMirrorsDisplay(id)) asleep=\(CGDisplayIsAsleep(id) != 0) \(CGDisplayPixelsWide(id))x\(CGDisplayPixelsHigh(id))")
}
