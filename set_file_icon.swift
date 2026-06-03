// set_file_icon.swift — set a file's Finder custom icon from an image.
//   swift set_file_icon.swift <icon.(icns|png)> <target-file>
import AppKit

let iconPath = CommandLine.arguments[1]
let target = CommandLine.arguments[2]

guard let image = NSImage(contentsOfFile: iconPath) else {
    FileHandle.standardError.write("cannot read icon: \(iconPath)\n".data(using: .utf8)!)
    exit(1)
}
let ok = NSWorkspace.shared.setIcon(image, forFile: target, options: [])
exit(ok ? 0 : 1)
