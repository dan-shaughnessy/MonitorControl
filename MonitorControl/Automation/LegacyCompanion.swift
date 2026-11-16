//  Copyright © MonitorControl contributors

import AppKit

/// The old app remains available until the user retires it from Automation settings.
/// Its settings are retained, even after its login job and app are moved to Trash.
enum LegacyCompanion {
  static let label = "io.github.dan-shaughnessy.lg-input-companion"
  static let bundleID = "io.github.dan-shaughnessy.LGInputCompanion"
  static var plist: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(self.label).plist") }
  static var legacyApp: URL { ConfigStore.monitorControl.legacyURL!.deletingLastPathComponent().appendingPathComponent("LGInputCompanion.app") }
  static var isPresent: Bool {
    FileManager.default.fileExists(atPath: self.plist.path)
      || !NSRunningApplication.runningApplications(withBundleIdentifier: self.bundleID).isEmpty
  }

  static func retire() throws {
    if FileManager.default.fileExists(atPath: self.plist.path) {
      let data = try Data(contentsOf: self.plist)
      let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
      guard values?["Label"] as? String == self.label else { throw self.error("The legacy login file has an unexpected label; it was left untouched.") }
    }
    let bootout = Process()
    bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    bootout.arguments = ["bootout", "gui/\(getuid())/\(self.label)"]
    bootout.standardError = FileHandle.nullDevice
    try bootout.run()
    bootout.waitUntilExit()
    // Verify it cannot relaunch before removing its login file.
    let check = Process()
    check.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    check.arguments = ["print", "gui/\(getuid())/\(self.label)"]
    check.standardOutput = FileHandle.nullDevice
    check.standardError = FileHandle.nullDevice
    try check.run()
    check.waitUntilExit()
    guard check.terminationStatus != 0 else { throw self.error("The companion login job is still loaded. Automation remains paused.") }
    for process in NSRunningApplication.runningApplications(withBundleIdentifier: self.bundleID) { process.terminate() }
    if FileManager.default.fileExists(atPath: self.plist.path) { try FileManager.default.trashItem(at: self.plist, resultingItemURL: nil) }
    if FileManager.default.fileExists(atPath: self.legacyApp.path) {
      guard Bundle(url: self.legacyApp)?.bundleIdentifier == self.bundleID else { throw self.error("The old app has an unexpected identity and was left untouched.") }
      try FileManager.default.trashItem(at: self.legacyApp, resultingItemURL: nil)
    }
  }

  private static func error(_ text: String) -> NSError { NSError(domain: "MonitorControl.AutomationMigration", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
}
