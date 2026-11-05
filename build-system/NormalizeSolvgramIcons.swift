// Compatibility alternate icons use 8-bit sRGB, even when Icon Composer exports 16-bit PNGs.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
let space=CGColorSpace(name:CGColorSpace.sRGB)!
for path in CommandLine.arguments.dropFirst() {
    let url=URL(fileURLWithPath:path)
    guard let source=CGImageSourceCreateWithURL(url as CFURL,nil), let image=CGImageSourceCreateImageAtIndex(source,0,nil), let context=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:0,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Cannot decode \(path)") }
    context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
    let data=NSMutableData()
    let output=CGImageDestinationCreateWithData(data,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(output,context.makeImage()!,nil)
    precondition(CGImageDestinationFinalize(output))
    try (data as Data).write(to:url,options:.atomic)
}
