//
//  SidecarLauncher
//  CLI to connect to a Sidecar device.
//
//  Created by Jovany Ocasio
//

import Foundation

enum Command : String {
    case Devices = "devices"
    case Connect = "connect"
}

func printHelp() {
    let help = """
        Commands:
            devices                  List names of reachable sidecar capable devices.
                                     Example: SidecarLauncher devices
            connect <device_name>    Connect to device with the specified name. Use quotes.
                                     Example: SidecarLauncher connect "Joe‘s iPad"
        """
    print(help)
}

if (CommandLine.arguments.count == 1) {
    print("Command not specified")
    printHelp()
    exit(1)
}

guard let cmd = Command(rawValue: CommandLine.arguments[1].lowercased()) else {
    print("Invalid command specified")
    printHelp()
    exit(1)
}

let targetDeviceName: String
if (cmd == .Connect) {
    if (CommandLine.arguments.count == 2) {
        print("Device name not specified")
        printHelp()
        exit(1)
    }
    targetDeviceName = CommandLine.arguments[2].lowercased()
} else {
    targetDeviceName = ""
}

guard let handle = dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY) else {
    fatalError("SidecarCore framework failed to open")
}

guard let sdm = NSClassFromString("SidecarDisplayManager") as? NSObject.Type else {
    fatalError("SidecarDisplayManager class not found")
}

guard let manager = sdm.perform(Selector(("sharedManager")))?.takeUnretainedValue() else {
    fatalError("Failed to instance of SidecarDisplayManger")
}

guard let devices = manager.perform(Selector(("devices")))?.takeUnretainedValue() as? [NSObject] else {
    fatalError("Failed to query reachable sidecar devices")
}

if (devices.isEmpty) {
    print("No sidecar capable devices detected")
    exit(0)
}

if (cmd == .Connect) {
    let targetDevice = devices.first(where: {
        let name = $0.perform(Selector(("name")))?.takeUnretainedValue() as! String
        return name.lowercased() == targetDeviceName
    })
    
    if let targetDevice = targetDevice {
        let dispatchGroup = DispatchGroup()
        let closure: @convention(block) (_ e: NSError?) -> Void = { e in
            defer {
                dispatchGroup.leave()
            }
            
            if let e = e {
                print(e)
            } else {
                print("connected")
            }
        }
        dispatchGroup.enter()
        _ = manager.perform(Selector(("connectToDevice:completion:")), with: targetDevice, with: closure)
        dispatchGroup.wait()
    } else {
        print("""
              \(targetDeviceName) is not in the list of available devices.
              Verify device name. For example "Joe's iPad" is different from "Joe‘s iPad" (notice the apostrophe)
              For accuracy, list the available devices and copy paste the device name.
              """)
    }
    
} else {
    let deviceNames = devices.map{$0.perform(Selector(("name")))?.takeUnretainedValue() as! String}
    print(deviceNames)
}
