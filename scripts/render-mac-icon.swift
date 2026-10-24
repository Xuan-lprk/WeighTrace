import AppKit
import SwiftUI

/// Raster export for the legacy Mac ICNS fallback. iOS keeps its unmasked square.
@main
struct RenderMacIcon {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3,
              let image = NSImage(contentsOfFile: CommandLine.arguments[1]) else {
            throw NSError(domain: "WeighTrace.Icon", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Expected input PNG and output PNG paths."])
        }
        // Optical padding is a project design choice, not a required Apple pixel grid.
        let content = Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: 824, height: 824)
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 8)
            .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let cgImage = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "WeighTrace.Icon", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Could not render the Mac icon."])
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
