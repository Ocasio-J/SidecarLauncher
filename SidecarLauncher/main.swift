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
enum Option : String {
    case WiredConnection = "-wired"
}

func printHelp() {
    let sidecarLauncher = "./SidecarLauncher"
    let help = """
        Commands:
            \(Command.Devices)
                       List names of reachable sidecar capable devices.
                       Example: \(sidecarLauncher) \(Command.Devices)
        
            \(Command.Connect) <device_name> [\(Option.WiredConnection)]
                       Connect to device with the specified name. Use quotes aroung device_name.
                       Example: \(sidecarLauncher) \(Command.Connect) "Joe‘s iPad" \(Option.WiredConnection)
                       
                       WARNING:
                       \(Option.WiredConnection) is an experimental option that tries to force a wired connection
                       when initializing a Sidecar session. The information below is based on limited observations.
                       An error is returned if there is no cable connected. It will not fallback to a wireless connection.
                       Once the connection succeeds with this option, the Sidecar session will *only* work with a cable
                       connection. If the cable is disconnected, it will not automatically fallback to a wireless connection.
                       Nor will it automatically reconnect when the cable is reconnected. The session needs to be terminated
                       and a new connection needs to be established.
        
            \(Command.Disconnect) <device_name>
                       Disconnect from device with the specified name. Use quotes.
                       Example: \(sidecarLauncher) \(Command.Disconnect) "Joe‘s iPad"
        
        Exit Codes:
            0    Command completed successfully
            1    Invalid input
            2    No reachable Sidecar devices detected
            4    SidecarCore private error encountered
        """
    print(help)
}

if (CommandLine.arguments.count == 1) {
    print("A command was not specified")
    printHelp()
    exit(1)
}

let cmdArg = CommandLine.arguments[1].lowercased()
guard let cmd = Command(rawValue: cmdArg) else {
    print("Invalid command specified: \(cmdArg)")
    printHelp()
    exit(1)
}

let targetDeviceName: String
var option: Option?
if (cmd == .Connect || cmd == .Disconnect) {
    if (CommandLine.arguments.count == 2) {
        print("A device name not specified")
        printHelp()
        exit(1)
    }
    
    targetDeviceName = CommandLine.arguments[2].lowercased()
    
    if (CommandLine.arguments.count == 4) {
        let optionArg = CommandLine.arguments[3].lowercased()
        guard let validOption = Option(rawValue: optionArg) else {
            print("Invalid option specified: \(optionArg)")
            printHelp()
            exit(1)
        }
        option = validOption
    }
} else {
    targetDeviceName = ""
}

guard let _ = dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY) else {
    fatalError("SidecarCore framework failed to open")
}

guard let cSidecarDisplayManager = NSClassFromString("SidecarDisplayManager") as? NSObject.Type else {
    fatalError("SidecarDisplayManager class not found")
}

guard let manager = cSidecarDisplayManager.perform(Selector(("sharedManager")))?.takeUnretainedValue() else {
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
    if (cmd == .Connect) {
        if (option == .WiredConnection) {
            guard let cSidecarDisplayConfig = NSClassFromString("SidecarDisplayConfig") as? NSObject.Type else {
                fatalError("SidecarDisplayConfig class not found")
            }
            
            let deviceConfig = cSidecarDisplayConfig.init()
            let setTransportSelector = Selector(("setTransport:"))
            let setTransportIMP = deviceConfig.method(for: setTransportSelector)
            let setTransport = unsafeBitCast(setTransportIMP, to:(@convention(c)(Any?, Selector, Int64)->Void).self)
            setTransport(deviceConfig, setTransportSelector, 2)
            
            let connectSelector = Selector(("connectToDevice:withConfig:completion:"))
            let connectIMP = manager.method(for: connectSelector)
            let connect = unsafeBitCast(connectIMP,to:(@convention(c)(Any?,Selector,Any?,Any?,Any?)->Void).self)
            connect(manager,connectSelector, targetDevice, deviceConfig, closure)
        } else {
            _ = manager.perform(Selector(("connectToDevice:completion:")), with: targetDevice, with: closure)
        }
    } else {
        assert(cmd == .Disconnect)
        _ = manager.perform(Selector(("disconnectFromDevice:completion:")), with: targetDevice, with: closure)
    }
    dispatchGroup.wait()
    
//    guard let deviceConfig = manager.perform(Selector(("configForDevice:")), with: targetDevice)?.takeUnretainedValue() as? NSObject else {
//        print("cry")
//        exit(99)
//    }
    
} else {
    let deviceNames = devices.map{$0.perform(Selector(("name")))?.takeUnretainedValue() as! String}
    for deviceName in deviceNames {
        print(deviceName)
    }
}
