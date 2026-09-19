import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Original diagnostic fixtures, not production interior artwork.
enum CalibrationTextures {
    static func write(to root:URL) throws {
        func image(_ name:String,width:Int=512,height:Int=512,draw:(CGContext)->Void) throws {
            guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {throw CocoaError(.fileWriteUnknown)}
            draw(context)
            guard let image=context.makeImage(),let output=CGImageDestinationCreateWithURL(root.appendingPathComponent(name) as CFURL,UTType.png.identifier as CFString,1,nil) else {throw CocoaError(.fileWriteUnknown)}
            CGImageDestinationAddImage(output,image,nil)
            guard CGImageDestinationFinalize(output) else {throw CocoaError(.fileWriteUnknown)}
        }
        try image("CalibrationShell.png",width:1280,height:256) { c in
            let colours:[(CGFloat,CGFloat,CGFloat)]=[(0.22,0.32,0.44),(0.43,0.22,0.27),(0.19,0.40,0.31),(0.33,0.34,0.35),(0.32,0.25,0.43)]
            for (face,rgb) in colours.enumerated() {
                for y in 0..<8 {for x in 0..<8 {
                    let f:CGFloat=(x+y)%2==0 ? 1:0.64
                    c.setFillColor(CGColor(red:rgb.0*f,green:rgb.1*f,blue:rgb.2*f,alpha:1))
                    c.fill(CGRect(x:face*256+x*32,y:y*32,width:32,height:32))
                }}
                // Asymmetric marker reveals face flips or stretched atlas mappings.
                c.setFillColor(CGColor(gray:0.8,alpha:1));c.fill(CGRect(x:face*256+12,y:210,width:54,height:12))
            }
        }
        try image("CalibrationFurniture.png") { c in
            c.setFillColor(CGColor(red:0.93,green:0.48,blue:0.12,alpha:1))
            c.fill(CGRect(x:95,y:155,width:322,height:225));c.fill(CGRect(x:60,y:115,width:392,height:70))
            c.setFillColor(CGColor(red:0.2,green:0.14,blue:0.10,alpha:1))
            c.fill(CGRect(x:95,y:55,width:24,height:62));c.fill(CGRect(x:393,y:55,width:24,height:62))
        }
        try image("CalibrationCurtains.png") { c in
            for side in [0,414] {for i in 0..<7 {
                c.setFillColor(CGColor(red:0.2+CGFloat(i%2)*0.1,green:0.65,blue:0.7,alpha:0.72))
                c.fill(CGRect(x:side+i*14,y:0,width:14,height:512))
            }}
        }
    }
}
