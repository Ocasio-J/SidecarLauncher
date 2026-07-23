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
    case Toggle     = "toggle"
}
enum Option : String {
    case WiredConnection = "-wired"
}

// --- Helper Functions ---

func findDevice(named name: String, in devices: [NSObject]) -> NSObject? {
    return devices.first { device in
        guard let deviceName = device.perform(Selector(("name")))?.takeUnretainedValue() as? String else {
            return false
        }
        return deviceName.lowercased() == name.lowercased()
    }
}

func performConnect(device: NSObject, deviceName: String, manager: NSObject, useWired: Bool, completion: @escaping (NSError?) -> Void) {
    let dispatchGroup = DispatchGroup()
    var errorResult: NSError? = nil
    
    let closure: @convention(block) (_ e: NSError?) -> Void = { e in
        errorResult = e
        dispatchGroup.leave()
    }
    
    dispatchGroup.enter()
    if useWired {
        guard let cSidecarDisplayConfig = NSClassFromString("SidecarDisplayConfig") as? NSObject.Type else {
            completion(NSError(domain: "SidecarLauncher", code: 4, userInfo: [NSLocalizedDescriptionKey: "SidecarDisplayConfig class not found"]))
            dispatchGroup.leave() // Ensure group is left on fatal error path
            return // Don't proceed
        }
        
        let deviceConfig = cSidecarDisplayConfig.init()
        let setTransportSelector = Selector(("setTransport:"))
        guard deviceConfig.responds(to: setTransportSelector) else {
            completion(NSError(domain: "SidecarLauncher", code: 4, userInfo: [NSLocalizedDescriptionKey: "SidecarDisplayConfig does not respond to setTransport:"]))
            dispatchGroup.leave()
            return
        }
        let setTransportIMP = deviceConfig.method(for: setTransportSelector)
        let setTransport = unsafeBitCast(setTransportIMP, to:(@convention(c)(Any?, Selector, Int64)->Void).self)
        setTransport(deviceConfig, setTransportSelector, 2) // 2 likely means wired
        
        let connectSelector = Selector(("connectToDevice:withConfig:completion:"))
        guard manager.responds(to: connectSelector) else {
            completion(NSError(domain: "SidecarLauncher", code: 4, userInfo: [NSLocalizedDescriptionKey: "Manager does not respond to connectToDevice:withConfig:completion:"]))
            dispatchGroup.leave()
            return
        }
        let connectIMP = manager.method(for: connectSelector)
        let connect = unsafeBitCast(connectIMP,to:(@convention(c)(Any?,Selector,Any?,Any?,Any?)->Void).self)
        connect(manager, connectSelector, device, deviceConfig, closure)
    } else {
         let connectSelector = Selector(("connectToDevice:completion:"))
         guard manager.responds(to: connectSelector) else {
             completion(NSError(domain: "SidecarLauncher", code: 4, userInfo: [NSLocalizedDescriptionKey: "Manager does not respond to connectToDevice:completion:"]))
             dispatchGroup.leave()
             return
         }
        _ = manager.perform(connectSelector, with: device, with: closure)
    }
    
    // Wait synchronously for the operation to complete in a CLI context
    dispatchGroup.wait()
    // Call completion handler after waiting
    completion(errorResult)
}

func performDisconnect(device: NSObject, deviceName: String, manager: NSObject, completion: @escaping (NSError?) -> Void) {
    let dispatchGroup = DispatchGroup()
    var errorResult: NSError? = nil
    
    let closure: @convention(block) (_ e: NSError?) -> Void = { e in
        errorResult = e
        dispatchGroup.leave()
    }

    dispatchGroup.enter()
    let disconnectSelector = Selector(("disconnectFromDevice:completion:"))
    guard manager.responds(to: disconnectSelector) else {
        completion(NSError(domain: "SidecarLauncher", code: 4, userInfo: [NSLocalizedDescriptionKey: "Manager does not respond to disconnectFromDevice:completion:"]))
        dispatchGroup.leave()
        return
    }
    _ = manager.perform(disconnectSelector, with: device, with: closure)
    
    // Wait synchronously for the operation to complete in a CLI context
    dispatchGroup.wait()
    // Call completion handler after waiting
    completion(errorResult)
}

func printHelp() {
    let sidecarLauncher = "./SidecarLauncher"
    let help = """
        Commands:
            \(Command.Devices.rawValue)
                       List names of reachable sidecar capable devices.
                       Example: \(sidecarLauncher) \(Command.Devices.rawValue)
        
            \(Command.Connect.rawValue) [<device_name>] [\(Option.WiredConnection.rawValue)]
                       Connect to device with the specified name (or first available if none specified).
                       Use quotes around device_name.
                       Example: \(sidecarLauncher) \(Command.Connect.rawValue) "Joe's iPad" \(Option.WiredConnection.rawValue)
                       Example (fallback): \(sidecarLauncher) \(Command.Connect.rawValue)
                       
                       WARNING:
                       \(Option.WiredConnection.rawValue) is an experimental option that tries to force a wired connection when initializing a Sidecar
                       session. The information below is based on limited observations.
                       An error is returned if there is no cable connected. It will not fallback to a wireless connection.
                       Once the connection succeeds with this option, the Sidecar session will *only* work with a cable
                       connection. If the cable is disconnected, it will not automatically fallback to a wireless connection.
                       Nor will it automatically reconnect when the cable is reconnected. The session needs to be terminated
                       and a new connection needs to be established.
        
            \(Command.Disconnect.rawValue) [<device_name>]
                       Disconnect from the specified device (or first available if none specified). Use quotes.
                       Example: \(sidecarLauncher) \(Command.Disconnect.rawValue) "Joe's iPad"
                       Example (fallback): \(sidecarLauncher) \(Command.Disconnect.rawValue)

            \(Command.Toggle.rawValue) [<device_name>]
                       If connected to the specified device (or the first device if none specified), disconnects.
                       If not connected, connects to the specified device (or the first device if none specified).
                       Example: \(sidecarLauncher) \(Command.Toggle.rawValue) "Joe's iPad"
                       Example (fallback): \(sidecarLauncher) \(Command.Toggle.rawValue)
        
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
if (cmd == .Connect || cmd == .Disconnect || cmd == .Toggle) {
    if (CommandLine.arguments.count > 2) {
        targetDeviceName = CommandLine.arguments[2].lowercased()
        
        if (cmd == .Connect && CommandLine.arguments.count > 3) {
            let optionArg = CommandLine.arguments[3].lowercased()
            guard let validOption = Option(rawValue: optionArg) else {
                print("Invalid option specified: \(optionArg)")
                printHelp()
                exit(1)
            }
            option = validOption
        } else {
             option = nil
        }
    } else {
         targetDeviceName = ""
    }
} else {
    targetDeviceName = ""
    option = nil
}

guard let _ = dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY) else {
    fatalError("SidecarCore framework failed to open")
}

guard let cSidecarDisplayManager = NSClassFromString("SidecarDisplayManager") as? NSObject.Type else {
    fatalError("SidecarDisplayManager class not found")
}

guard let manager = cSidecarDisplayManager.perform(Selector(("sharedManager")))?.takeUnretainedValue() as? NSObject else {
    fatalError("Failed to get instance of SidecarDisplayManger or cast to NSObject")
}

guard let devices = manager.perform(Selector(("devices")))?.takeUnretainedValue() as? [NSObject] else {
    fatalError("Failed to query reachable sidecar devices")
}

if (devices.isEmpty) {
    print("No sidecar capable devices detected")
    exit(2)
}

if cmd == .Devices {
    let deviceNames = devices.map{$0.perform(Selector(("name")))?.takeUnretainedValue() as! String}
    for deviceName in deviceNames {
        print(deviceName)
    }
    exit(0)
} else if cmd == .Connect {
    var deviceToConnect: NSObject?
    var actualDeviceNameToConnect: String = ""

    if !targetDeviceName.isEmpty {
        print("Connect: Using specified device '\(targetDeviceName)'")
        deviceToConnect = findDevice(named: targetDeviceName, in: devices)
        guard deviceToConnect != nil else {
             print("'\(targetDeviceName)' not found among reachable devices.")
             let deviceNames = devices.map{$0.perform(Selector(("name")))?.takeUnretainedValue() as! String}
             print("Available devices: \(deviceNames.joined(separator: ", "))")
             exit(3)
        }
        actualDeviceNameToConnect = targetDeviceName // Already lowercased during arg parsing
    } else {
        print("Connect: No device specified, using first available device.")
        // devices list is guaranteed not empty here due to earlier check
        deviceToConnect = devices[0]
        actualDeviceNameToConnect = deviceToConnect!.perform(Selector(("name")))?.takeUnretainedValue() as? String ?? "Unknown Device"
        print("Found device: \(actualDeviceNameToConnect)")
    }

    guard let finalDeviceToConnect = deviceToConnect else {
         print("Error: Could not determine device to connect.")
         exit(1)
    }
    
    print("Attempting to connect to '\(actualDeviceNameToConnect)'...")
    performConnect(device: finalDeviceToConnect, deviceName: actualDeviceNameToConnect, manager: manager, useWired: (option == .WiredConnection)) { error in
        if let error = error {
            print("Error during connection: \(error.localizedDescription)")
            if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                 print("Underlying Error: \(underlyingError.localizedDescription)")
            }
            exit(4)
        } else {
            print("Successfully connected to '\(actualDeviceNameToConnect)'")
            exit(0)
        }
    }
    exit(4)
} else if cmd == .Disconnect {
    var deviceToDisconnect: NSObject?
    var actualDeviceNameToDisconnect: String = ""

    if !targetDeviceName.isEmpty {
        print("Disconnect: Using specified device '\(targetDeviceName)'")
        deviceToDisconnect = findDevice(named: targetDeviceName, in: devices)
        guard deviceToDisconnect != nil else {
             print("'\(targetDeviceName)' not found among reachable devices.")
             let deviceNames = devices.map{$0.perform(Selector(("name")))?.takeUnretainedValue() as! String}
             print("Available devices: \(deviceNames.joined(separator: ", "))")
             exit(3)
        }
        actualDeviceNameToDisconnect = targetDeviceName // Already lowercased
    } else {
        print("Disconnect: No device specified, using first available device.")
        // devices list is guaranteed not empty here
        deviceToDisconnect = devices[0]
        actualDeviceNameToDisconnect = deviceToDisconnect!.perform(Selector(("name")))?.takeUnretainedValue() as? String ?? "Unknown Device"
        print("Found device: \(actualDeviceNameToDisconnect)")
    }
    
    guard let finalDeviceToDisconnect = deviceToDisconnect else {
         print("Error: Could not determine device to disconnect.")
         exit(1)
    }
    
    print("Attempting to disconnect from '\(actualDeviceNameToDisconnect)'...")
    performDisconnect(device: finalDeviceToDisconnect, deviceName: actualDeviceNameToDisconnect, manager: manager) { error in
        if let error = error {
            print("Error during disconnection: \(error.localizedDescription)")
             if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                 print("Underlying Error: \(underlyingError.localizedDescription)")
            }
            exit(4)
        } else {
            print("Successfully disconnected from '\(actualDeviceNameToDisconnect)'")
            exit(0)
        }
    }
    exit(4)
} else if cmd == .Toggle {
    var deviceToToggle: NSObject?
    var actualDeviceNameToToggle: String = ""

    if !targetDeviceName.isEmpty {
        print("Toggle: Using specified device '\(targetDeviceName)'")
        deviceToToggle = findDevice(named: targetDeviceName, in: devices)
        guard deviceToToggle != nil else {
             print("'\(targetDeviceName)' not found among reachable devices.")
             let deviceNames = devices.map{$0.perform(Selector(("name")))?.takeUnretainedValue() as! String}
             print("Available devices: \(deviceNames.joined(separator: ", "))")
             exit(3)
        }
        actualDeviceNameToToggle = targetDeviceName
    } else {
        print("Toggle: No device specified, using first available device.")
        if devices.isEmpty {
             print("No sidecar capable devices detected.")
             exit(2)
        }
        deviceToToggle = devices[0]
        actualDeviceNameToToggle = deviceToToggle!.perform(Selector(("name")))?.takeUnretainedValue() as? String ?? "Unknown Device"
        print("Found device: \(actualDeviceNameToToggle)")
    }

    guard let finalDeviceToToggle = deviceToToggle else {
         print("Error: Could not determine device to toggle.")
         exit(1)
    }
    
    print("Attempting to disconnect '\(actualDeviceNameToToggle)' (in case already connected)...")
    performDisconnect(device: finalDeviceToToggle, deviceName: actualDeviceNameToToggle, manager: manager) { disconnectError in
        if disconnectError == nil {
            print("Toggle: Successfully disconnected '\(actualDeviceNameToToggle)'.")
            exit(0)
        } else {
            print("Toggle: Disconnect failed (may not have been connected). Attempting connection to '\(actualDeviceNameToToggle)'...")
            
            performConnect(device: finalDeviceToToggle, deviceName: actualDeviceNameToToggle, manager: manager, useWired: false) { connectError in
                if let connectError = connectError {
                    print("Error during connection: \(connectError.localizedDescription)")
                    if let underlyingError = connectError.userInfo[NSUnderlyingErrorKey] as? NSError {
                         print("Underlying Error: \(underlyingError.localizedDescription)")
                    }
                    exit(4)
                } else {
                    print("Toggle: Successfully connected to '\(actualDeviceNameToToggle)'.")
                    exit(0)
                }
            }
            exit(4)
        }
    }
    exit(4)
}
