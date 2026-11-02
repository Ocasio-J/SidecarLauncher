import Foundation

func die(_ code: Int32, _ message: String) -> Never {
    FileHandle.standardError.write(("ERR: " + message + "\n").data(using: .utf8)!)
    exit(code)
}

guard dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY) != nil else {
    die(3, "cannot load SidecarCore")
}
guard let managerClass = NSClassFromString("SidecarDisplayManager") as? NSObject.Type else {
    die(3, "SidecarDisplayManager class not found")
}
guard let manager = managerClass.perform(Selector(("sharedManager")))?.takeUnretainedValue() as? NSObject else {
    die(3, "SidecarDisplayManager.sharedManager returned nothing")
}

let accessor = Selector(("connectedDevices"))
guard manager.responds(to: accessor) else {
    die(3, "SidecarDisplayManager does not respond to connectedDevices (private API changed)")
}
guard let raw = manager.value(forKey: "connectedDevices") else {
    die(3, "connectedDevices is nil")
}
guard let devices = raw as? [Any] else {
    die(3, "connectedDevices is not an array (\(type(of: raw)))")
}

print("connected=\(devices.count)")
for device in devices {
    var name = "unknown"
    if let object = device as? NSObject, object.responds(to: Selector(("name"))),
       let value = object.perform(Selector(("name")))?.takeUnretainedValue() as? String {
        name = value
    }
    print("device=\(name)")
}

exit(devices.isEmpty ? 1 : 0)
