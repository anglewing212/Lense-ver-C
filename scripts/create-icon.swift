import AppKit

let directory = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
for base in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = base*scale
        let context = CGContext(data:nil,width:pixels,height:pixels,bitsPerComponent:8,bytesPerRow:pixels*4,
                                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x:CGFloat(pixels)/1024,y:CGFloat(pixels)/1024)
        context.setFillColor(CGColor(gray:0,alpha:1))
        context.addPath(CGPath(roundedRect:CGRect(x:40,y:40,width:944,height:944),cornerWidth:210,cornerHeight:210,transform:nil))
        context.fillPath()
        context.setStrokeColor(CGColor(gray:1,alpha:1))
        context.setLineWidth(40)
        context.strokeEllipse(in:CGRect(x:272,y:272,width:480,height:480))
        let png = NSBitmapImageRep(cgImage:context.makeImage()!).representation(using:.png,properties:[:])!
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to:directory.appendingPathComponent("icon_\(base)x\(base)\(suffix).png"))
    }
}
