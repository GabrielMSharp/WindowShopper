import RealityKit
import Foundation

public enum WindowGeometry {
    /// Convex counter-clockwise silhouette in physical metres. The room behind
    /// the aperture remains a box; no discarded/transparent corner fragments.
    public static func outline(size:SIMD2<Float>,shape:WindowShape) -> [SIMD2<Float>] {
        let w=size.x/2,h=size.y/2
        switch shape {
        case .rectangle:return [[-w,-h],[w,-h],[w,h],[-w,h]]
        case .oval:return (0..<64).map {let a=Float($0)*2 * .pi/64;return [cos(a)*w,sin(a)*h]}
        case .arch:
            return [[-w,-h],[w,-h]]+(0...32).map {let a=Float($0) * .pi/32;return [cos(a)*w,sin(a)*h]}
        case .chamfered:
            let r=min(w,h)*0.3
            return [[-w+r,-h],[w-r,-h],[w,-h+r],[w,h-r],[w-r,h],[-w+r,h],[-w,h-r],[-w,-h+r]]
        case .rounded,.capsule:
            let r=min(w,h)*(shape == .capsule ? 1:0.32)
            let centres:[SIMD2<Float>]=[[w-r,-h+r],[w-r,h-r],[-w+r,h-r],[-w+r,-h+r]]
            return centres.enumerated().flatMap {i,c in
                (0...12).map {j in let a=(-Float.pi/2)+Float(i)*Float.pi/2+Float(j)*Float.pi/24;return c+SIMD2<Float>(cos(a),sin(a))*r}
            }
        }
    }
    @MainActor public static func surface(size:SIMD2<Float>,shape:WindowShape,roomSize:SIMD2<Float>? = nil,offset:SIMD2<Float> = .zero) throws -> MeshResource {
        let edge=outline(size:size,shape:shape)
        var mesh=MeshDescriptor(name:"Window_"+shape.rawValue)
        mesh.positions = .init([[0,0,0]]+edge.map{[$0.x,$0.y,0]})
        mesh.normals = .init(Array(repeating:[0,0,1],count:edge.count+1))
        mesh.textureCoordinates = .init(([SIMD2<Float>.zero]+edge).map{($0+offset)/(roomSize ?? size)+SIMD2<Float>(repeating:0.5)})
        mesh.primitives = .triangles(edge.indices.flatMap{[0,UInt32($0+1),UInt32(($0+1)%edge.count+1)]})
        return try MeshResource.generate(from:[mesh])
    }
    @MainActor public static func frame(size:SIMD2<Float>,shape:WindowShape,thickness:Float=0.09) throws -> MeshResource {
        let inside=outline(size:size,shape:shape)
        // Radial expansion keeps every inner edge identical to the aperture.
        let outside=inside.map{$0*(size+SIMD2<Float>(repeating:thickness*2))/size}
        var points:[SIMD3<Float>]=[],indices:[UInt32]=[]
        func quad(_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ c:SIMD3<Float>,_ d:SIMD3<Float>) {
            let n=UInt32(points.count);points += [a,b,c,d];indices += [n,n+1,n+2,n,n+2,n+3]
        }
        for i in inside.indices {
            let j=(i+1)%inside.count,a=inside[i],b=inside[j],c=outside[i],d=outside[j]
            quad([a.x,a.y,0.055],[c.x,c.y,0.055],[d.x,d.y,0.055],[b.x,b.y,0.055])
            quad([a.x,a.y,-0.075],[a.x,a.y,0.055],[b.x,b.y,0.055],[b.x,b.y,-0.075])
            quad([c.x,c.y,0.055],[c.x,c.y,-0.075],[d.x,d.y,-0.075],[d.x,d.y,0.055])
        }
        var mesh=MeshDescriptor(name:"WindowFrame");mesh.positions = .init(points);mesh.primitives = .triangles(indices)
        return try MeshResource.generate(from:[mesh])
    }
}
