//
//  SidecarLauncher
//  CLI to connect to a Sidecar device.
//
//  Created by Jovany Ocasio
//

import Foundation

enum Command : String {
    case Devices    = "devices"
    case Connect    = "connect"
    case Disconnect = "disconnect"
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
if (cmd == .Connect || cmd == .Disconnect) {
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
    fatalError("Failed to get instance of SidecarDisplayManger")
}

guard let devices = manager.perform(Selector(("devices")))?.takeUnretainedValue() as? [NSObject] else {
    fatalError("Failed to query reachable sidecar devices")
}

if (devices.isEmpty) {
    print("No sidecar capable devices detected")
    exit(2)
}

if (cmd == .Connect || cmd == .Disconnect) {
    let targetDevice = devices.first(where: {
        let name = $0.perform(Selector(("name")))?.takeUnretainedValue() as! String
        return name.lowercased() == targetDeviceName
    })
    
    guard let targetDevice = targetDevice else {
        print("""
              \(targetDeviceName) is not in the list of available devices.
              Verify device name. For example "Joe's iPad" is different from "Joe‘s iPad" (notice the apostrophe)
              For accuracy, list the available devices and copy paste the device name.
              """)
        exit(3)
    }
    
    let dispatchGroup = DispatchGroup()
    let closure: @convention(block) (_ e: NSError?) -> Void = { e in
        defer {
            dispatchGroup.leave()
        }
        
        if let e = e {
            print(e)
            exit(4)
        } else {
            print(cmd == .Connect ? "connected" : "disconnected")
        }
    }
    dispatchGroup.enter()
    let method = (cmd == .Connect ? "connectToDevice:completion:" : "disconnectFromDevice:completion:")
    _ = manager.perform(Selector((method)), with: targetDevice, with: closure)
    dispatchGroup.wait()
    
} else {
    let deviceNames = devices.map{$0.perform(Selector(("name")))?.takeUnretainedValue() as! String}
    for deviceName in deviceNames {
        print(deviceName)
    }
}
