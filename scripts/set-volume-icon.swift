// Sets the custom volume icon (and the Finder custom-icon bit) on a mounted
// volume. Run with the swift interpreter: swift set-volume-icon.swift <volume> <icns>
// NSWorkspace.setIcon replaces the deprecated SetFile tool.
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: set-volume-icon.swift <volumePath> <icnsPath>\n".data(using: .utf8)!)
    exit(64)
}
guard let icon = NSImage(contentsOfFile: args[2]) else {
    FileHandle.standardError.write("could not load icon \(args[2])\n".data(using: .utf8)!)
    exit(1)
}
let ok = NSWorkspace.shared.setIcon(icon, forFile: args[1], options: [])
exit(ok ? 0 : 1)
