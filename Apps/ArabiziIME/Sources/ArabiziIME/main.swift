import AppKit
import InputMethodKit
import os

// macOS starts this app when the user selects the input source. It only serves IMK connections:
// one ArabiziInputController per text field, created by the server (Info.plist InputMethodServerControllerClass).
let log = Logger(subsystem: "lb.aub.arabizi", category: "ime")

guard let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
      let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
else {
    log.fault("Could not start the IMK server: check InputMethodConnectionName in Info.plist")
    exit(1)
}
log.info("ArabiziIME started")
withExtendedLifetime(server) {
    NSApplication.shared.run()
}
