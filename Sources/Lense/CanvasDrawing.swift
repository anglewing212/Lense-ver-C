import AppKit

func drawSelectionCorners(_ rect: CGRect) {
    guard !rect.isEmpty else { return }
    NSColor.gray.withAlphaComponent(0.5).setFill()
    for point in [CGPoint(x:rect.minX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.minY),
                  CGPoint(x:rect.minX,y:rect.maxY),CGPoint(x:rect.maxX,y:rect.maxY)] {
        NSBezierPath(ovalIn:CGRect(x:point.x-3.5,y:point.y-3.5,width:7,height:7)).fill()
    }
}
