import CoreText
extension FilePickerAuditApp {
 @MainActor func auditProfileNames() {
  if let icon=UIImage(named:"MarkAsRead") {
   verify(icon.size==CGSize(width:24,height:24),"Read eye uses the same 24pt canvas as menu icons")
   for (name,color) in [("dark",UIColor.white),("light",UIColor.black)] {
    let format=UIGraphicsImageRendererFormat();format.scale=1
    let image=UIGraphicsImageRenderer(size:icon.size,format:format).image { _ in icon.withTintColor(color,renderingMode:.alwaysOriginal).draw(at:.zero) }
    if let cg=image.cgImage, let rgba=CGContext(data:nil,width:cg.width,height:cg.height,bitsPerComponent:8,bytesPerRow:cg.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) {
     rgba.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height))
     let pixels=rgba.data!.bindMemory(to:UInt8.self,capacity:cg.width*cg.height*4)
     var ink=0;var matching=true
     for y in 0..<cg.height {for x in 0..<cg.width {
      let n=y*rgba.bytesPerRow+x*4
      if pixels[n+3]>240 {
       ink += 1
       if name=="dark" { matching = matching && pixels[n]>240 && pixels[n+1]>240 && pixels[n+2]>240 }
       else { matching = matching && pixels[n]<15 && pixels[n+1]<15 && pixels[n+2]<15 }
      }
     }}
     verify(ink>10 && matching,"Read eye follows the menu tint in "+name)
     let center=12*rgba.bytesPerRow+12*4
     verify(pixels[center+3]==0,"Read eye has no diagonal through its center in "+name)
     let directory=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
     try? image.pngData()?.write(to:directory.appendingPathComponent("read-eye-"+name+".png"))
    } else {verify(false,"Read eye rasterizes in "+name)}
   }
  } else {verify(false,"Production read-eye asset is linked")}
 }
}
