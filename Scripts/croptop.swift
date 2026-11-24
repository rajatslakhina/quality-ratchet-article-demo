import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// usage: swift croptop.swift <in.png> <out.png> <height>  — keeps the top <height> pixels
let args = CommandLine.arguments
guard args.count == 4, let height = Int(args[3]),
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
      let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: min(height, image.height))),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { print("crop failed"); exit(1) }
CGImageDestinationAddImage(dest, cropped, nil)
exit(CGImageDestinationFinalize(dest) ? 0 : 1)
