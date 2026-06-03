// make_icon.swift — render the menu-bar moon (SF Symbol moon.zzz) into a
// macOS app icon PNG. Output: a single square PNG at the requested size.
//   swift make_icon.swift <size> <out.png>
import AppKit

let size = CGFloat(Double(CommandLine.arguments[1]) ?? 1024)
let outPath = CommandLine.arguments[2]

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// --- rounded-rect "squircle"-ish background with a night-sky gradient ---
let inset = size * 0.06                      // macOS icons leave a small margin
let rect = NSRect(x: inset, y: inset, width: size - inset*2, height: size - inset*2)
let radius = rect.width * 0.225              // Big Sur corner radius ratio
let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
path.addClip()

let top = NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.42, alpha: 1)   // indigo
let bot = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.20, alpha: 1)   // deep navy
let grad = NSGradient(starting: top, ending: bot)!
grad.draw(in: rect, angle: -90)

// --- the moon glyph, centered ---
let glyphPt = size * 0.62
let cfg = NSImage.SymbolConfiguration(pointSize: glyphPt, weight: .regular)
if let sym = NSImage(systemSymbolName: "moon.zzz.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(cfg) {
    let tinted = NSImage(size: sym.size)
    tinted.lockFocus()
    NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.86, alpha: 1).set()  // warm moonlight
    let r = NSRect(origin: .zero, size: sym.size)
    sym.draw(in: r)
    r.fill(using: .sourceAtop)
    tinted.unlockFocus()

    let gw = sym.size.width, gh = sym.size.height
    let gx = (size - gw) / 2
    let gy = (size - gh) / 2 - size * 0.01
    tinted.draw(in: NSRect(x: gx, y: gy, width: gw, height: gh))
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let bmp = NSBitmapImageRep(data: tiff),
      let png = bmp.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
_ = ctx
