import Foundation
import CoreGraphics
import IOKit.pwr_mgt

let REFRESH = 60.0
let VENDOR: UInt32 = 0x5644
let SIDECAR_VENDOR: UInt32 = 0x6161706c
let ASSERTION_NAME = "local.sidecar.vdisp: Sidecar session"
let PROBE_TIMEOUT = 5.0
let EVALUATE_INTERVAL = 30.0
let SHUTDOWN_DELAY = 0.5

let env = ProcessInfo.processInfo.environment

func dimension(_ key: String, default fallback: Int32) -> Int32 {
    if let raw = env[key], let value = Int32(raw), value > 0 { return value }
    return fallback
}

let W = dimension("VDISP_WIDTH", default: 640)
let H = dimension("VDISP_HEIGHT", default: 480)

let pid = UInt32(truncatingIfNeeded: getpid())
let secs = UInt32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970))
let ident = (pid & 0xffff) | ((secs & 0xffff) << 16)
let product = ((pid & 0xffff) << 16) | (secs & 0xffff)

func hex(_ v: UInt32) -> String { "0x" + String(v, radix: 16) }

func cls(_ n: String) -> NSObject.Type {
    guard let c = NSClassFromString(n) as? NSObject.Type else { print("missing class \(n)"); exit(1) }
    return c
}

let iso: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    return formatter
}()

func log(_ message: String) {
    print("\(iso.string(from: Date())) \(message)")
    fflush(stdout)
}

let keepAwake = env["VDISP_KEEP_AWAKE"] != "0"
let maxHold = Double(env["KEEP_AWAKE_MAX_HOLD"] ?? "") ?? 0

let probeQueue = DispatchQueue(label: "local.sidecar.vdisp.probe")
let probeLock = NSLock()

var assertionHeld = false
var assertion: IOPMAssertionID = 0
var heldSince: Date?
var heldDisplayID: CGDirectDisplayID?
var backstopTripped = false
var lastFailure: String?
var probeInFlight = false
var probeProcess: Process?
var probeTimedOut = false
var probeTimer: DispatchSourceTimer?
var stopping = false

let descC = cls("CGVirtualDisplayDescriptor")
let setC  = cls("CGVirtualDisplaySettings")
let modeC = cls("CGVirtualDisplayMode")
let dispC = cls("CGVirtualDisplay")

func onlineSidecarDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
    return ids.prefix(Int(count)).filter { CGDisplayVendorNumber($0) == SIDECAR_VENDOR }
}

func connectedBinary() -> String {
    let executable = Bundle.main.executablePath ?? CommandLine.arguments[0]
    return URL(fileURLWithPath: executable).deletingLastPathComponent().appendingPathComponent("connected").path
}

func connectedCount(_ output: String) -> Int? {
    for line in output.split(separator: "\n") where line.hasPrefix("connected=") {
        if let value = Int(line.dropFirst("connected=".count)) { return value }
    }
    return nil
}

func armProbeTimer() {
    cancelProbeTimer()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + PROBE_TIMEOUT)
    timer.setEventHandler {
        probeLock.lock()
        if let process = probeProcess, process.isRunning {
            probeTimedOut = true
            kill(process.processIdentifier, SIGTERM)
        }
        probeLock.unlock()
    }
    timer.resume()
    probeTimer = timer
}

func cancelProbeTimer() {
    probeTimer?.cancel()
    probeTimer = nil
}

func acquireAssertion(connected: Int, displayID: CGDirectDisplayID) {
    var id: IOPMAssertionID = 0
    let status = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        ASSERTION_NAME as CFString,
        &id)
    guard status == kIOReturnSuccess else {
        log("keep-awake off (assertion=\(status))")
        return
    }
    assertion = id
    assertionHeld = true
    heldDisplayID = displayID
    heldSince = Date()
    lastFailure = nil
    log("keep-awake on (connected=\(connected))")
}

func releaseAssertion(reason: String) {
    if assertionHeld {
        IOPMAssertionRelease(assertion)
        assertionHeld = false
        log("keep-awake off (\(reason))")
    } else if reason != lastFailure {
        log("keep-awake off (\(reason))")
    }
    lastFailure = reason
    heldDisplayID = nil
    heldSince = nil
    backstopTripped = false
}

func applyEvidence(connected: Int, displayID: CGDirectDisplayID) {
    if let previous = heldDisplayID, previous != displayID {
        heldDisplayID = displayID
        heldSince = Date()
        backstopTripped = false
    }
    if backstopTripped { return }
    if assertionHeld {
        if maxHold > 0, let since = heldSince, Date().timeIntervalSince(since) >= maxHold {
            IOPMAssertionRelease(assertion)
            assertionHeld = false
            heldSince = nil
            backstopTripped = true
            lastFailure = "backstop"
            log("keep-awake off (backstop)")
        }
        return
    }
    acquireAssertion(connected: connected, displayID: displayID)
}

func applyProbe(status: Int32, output: String, timedOut: Bool) {
    if stopping { return }
    if timedOut { releaseAssertion(reason: "probe=timeout"); return }
    guard status == 0 else { releaseAssertion(reason: "probe=\(status)"); return }
    let count = connectedCount(output) ?? 1
    guard count >= 1 else { releaseAssertion(reason: "probe=0"); return }
    let displays = onlineSidecarDisplays()
    guard let displayID = displays.max() else { releaseAssertion(reason: "no sidecar display"); return }
    applyEvidence(connected: count, displayID: displayID)
}

func runProbe() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: connectedBinary())
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    probeLock.lock()
    probeProcess = process
    probeTimedOut = false
    probeLock.unlock()
    var status: Int32 = -1
    var output = ""
    do {
        try process.run()
        DispatchQueue.main.async { armProbeTimer() }
        process.waitUntilExit()
        status = process.terminationStatus
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        output = String(data: data, encoding: .utf8) ?? ""
    } catch {
        status = -1
    }
    probeLock.lock()
    let timedOut = probeTimedOut
    probeTimedOut = false
    probeProcess = nil
    probeLock.unlock()
    DispatchQueue.main.async {
        cancelProbeTimer()
        probeInFlight = false
        applyProbe(status: status, output: output, timedOut: timedOut)
    }
}

func evaluate() {
    if stopping { return }
    if !keepAwake { releaseAssertion(reason: "env"); return }
    guard !probeInFlight else { return }
    probeInFlight = true
    probeQueue.async { runProbe() }
}

func requestEvaluation() {
    probeQueue.async { DispatchQueue.main.async { evaluate() } }
}

let desc = descC.init()
desc.setValue("VirtualEDID", forKey: "name")
desc.setValue(UInt32(W), forKey: "maxPixelsWide")
desc.setValue(UInt32(H), forKey: "maxPixelsHigh")
desc.setValue(NSValue(size: CGSize(width: 160, height: 120)), forKey: "sizeInMillimeters")
desc.setValue(VENDOR, forKey: "vendorID")
desc.setValue(product, forKey: "productID")
desc.setValue(ident, forKey: "serialNum")
desc.setValue(DispatchQueue.main, forKey: "queue")

var display: NSObject? = dispC.init()
guard let created = display?.perform(Selector(("initWithDescriptor:")), with: desc)?.takeUnretainedValue() as? NSObject else {
    print("initWithDescriptor failed: identity vendor=\(hex(VENDOR)) product=\(hex(product)) serial=\(hex(ident)) pid=\(pid)")
    print("  a display with the same identity is probably already present (vendor/product/serial), or there is no window server")
    print("  each instance derives product and serial from pid+time: if it fails with fresh values too, the cause is not a collision")
    exit(1)
}
var virtualDisplay: NSObject? = created

let mode = modeC.init()
let sel = Selector(("initWithWidth:height:refreshRate:"))
typealias ModeInit = @convention(c) (AnyObject, Selector, UInt32, UInt32, Double) -> AnyObject
let m = unsafeBitCast(mode.method(for: sel), to: ModeInit.self)(mode, sel, UInt32(W), UInt32(H), REFRESH)

let settings = setC.init()
settings.setValue(UInt32(1), forKey: "hiDPI")
settings.setValue([m], forKey: "modes")
virtualDisplay?.perform(Selector(("applySettings:")), with: settings)
log("virtual display created \(W)x\(H) hiDPI (default 640x480, VDISP_WIDTH/VDISP_HEIGHT override it), vendor=\(hex(VENDOR)) product=\(hex(product)) serial=\(hex(ident)) pid=\(pid) — waiting")

let refreshTimer = DispatchSource.makeTimerSource(queue: .main)
refreshTimer.schedule(deadline: .now() + EVALUATE_INTERVAL, repeating: EVALUATE_INTERVAL)
refreshTimer.setEventHandler { evaluate() }
refreshTimer.resume()

CGDisplayRegisterReconfigurationCallback({ _, _, _ in
    requestEvaluation()
}, nil)

func shutdown(_ name: String) {
    if stopping { return }
    stopping = true
    log("shutdown (\(name))")
    releaseAssertion(reason: "shutdown")
    virtualDisplay = nil
    display = nil
    refreshTimer.cancel()
    cancelProbeTimer()
    DispatchQueue.main.asyncAfter(deadline: .now() + SHUTDOWN_DELAY) { exit(0) }
}

_ = signal(SIGTERM, SIG_IGN)
_ = signal(SIGINT, SIG_IGN)
let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
terminateSource.setEventHandler { shutdown("SIGTERM") }
terminateSource.resume()
let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interruptSource.setEventHandler { shutdown("SIGINT") }
interruptSource.resume()

evaluate()
RunLoop.main.run()
