import Foundation
import CoreGraphics

let W = 2642, H = 1836, REFRESH = 60.0
let VENDOR: UInt32 = 0x5644

let pid = UInt32(truncatingIfNeeded: getpid())
let secs = UInt32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970))
let ident = (pid & 0xffff) | ((secs & 0xffff) << 16)
let product = ((pid & 0xffff) << 16) | (secs & 0xffff)

func hex(_ v: UInt32) -> String { "0x" + String(v, radix: 16) }

func cls(_ n: String) -> NSObject.Type {
    guard let c = NSClassFromString(n) as? NSObject.Type else { print("missing class \(n)"); exit(1) }
    return c
}
let descC = cls("CGVirtualDisplayDescriptor")
let setC  = cls("CGVirtualDisplaySettings")
let modeC = cls("CGVirtualDisplayMode")
let dispC = cls("CGVirtualDisplay")

let desc = descC.init()
desc.setValue("VirtualEDID", forKey: "name")
desc.setValue(UInt32(W), forKey: "maxPixelsWide")
desc.setValue(UInt32(H), forKey: "maxPixelsHigh")
desc.setValue(NSValue(size: CGSize(width: 500, height: 350)), forKey: "sizeInMillimeters")
desc.setValue(VENDOR, forKey: "vendorID")
desc.setValue(product, forKey: "productID")
desc.setValue(ident, forKey: "serialNum")
desc.setValue(DispatchQueue.main, forKey: "queue")

let display = dispC.init()
guard let d = display.perform(Selector(("initWithDescriptor:")), with: desc)?.takeUnretainedValue() as? NSObject else {
    print("initWithDescriptor failed: identity vendor=\(hex(VENDOR)) product=\(hex(product)) serial=\(hex(ident)) pid=\(pid)")
    print("  a display with the same identity is probably already present (vendor/product/serial), or there is no window server")
    print("  each instance derives product and serial from pid+time: if it fails with fresh values too, the cause is not a collision")
    exit(1)
}

let mode = modeC.init()
let sel = Selector(("initWithWidth:height:refreshRate:"))
typealias ModeInit = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> AnyObject
let m = unsafeBitCast(mode.method(for: sel), to: ModeInit.self)(mode, sel, UInt32(W), UInt32(H), REFRESH)

let settings = setC.init()
settings.setValue(UInt32(1), forKey: "hiDPI")
settings.setValue([m], forKey: "modes")
d.perform(Selector(("applySettings:")), with: settings)
print("virtual display created \(W)x\(H) hiDPI, vendor=\(hex(VENDOR)) product=\(hex(product)) serial=\(hex(ident)) pid=\(pid) — waiting")
fflush(stdout)
RunLoop.main.run()
