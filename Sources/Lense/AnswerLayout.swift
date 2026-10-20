import CoreGraphics

func freeAnswerRect(size: CGSize, near origin: CGPoint, bounds: CGRect, protected: CGRect,
                    occupied: [CGRect], minimum: CGSize) -> CGRect? {
    var spaces = [bounds.insetBy(dx:8,dy:8)]
    for blocked in [protected] + occupied {
        spaces = spaces.flatMap { space -> [CGRect] in
            let cut = space.intersection(blocked.insetBy(dx:-6,dy:-6))
            guard !cut.isNull, !cut.isEmpty else { return [space] }
            return [CGRect(x:space.minX,y:space.minY,width:cut.minX-space.minX,height:space.height),
                    CGRect(x:cut.maxX,y:space.minY,width:space.maxX-cut.maxX,height:space.height),
                    CGRect(x:cut.minX,y:space.minY,width:cut.width,height:cut.minY-space.minY),
                    CGRect(x:cut.minX,y:cut.maxY,width:cut.width,height:space.maxY-cut.maxY)]
                .filter { $0.width >= minimum.width && $0.height >= minimum.height }
        }
    }
    let candidates = spaces.filter { $0.width >= minimum.width && $0.height >= minimum.height }.map { space in
        CGRect(x:max(space.minX,min(origin.x,space.maxX-min(size.width,space.width))),
               y:max(space.minY,min(origin.y,space.maxY-min(size.height,space.height))),
               width:min(size.width,space.width),height:min(size.height,space.height))
    }
    return candidates.min { a,b in
        let aFits = a.width >= size.width && a.height >= size.height
        let bFits = b.width >= size.width && b.height >= size.height
        if aFits != bFits { return aFits }
        if !aFits {
            let aArea = a.width*a.height, bArea = b.width*b.height
            if abs(aArea-bArea)>1 { return aArea>bArea }
        }
        return hypot(a.minX-origin.x,a.minY-origin.y) < hypot(b.minX-origin.x,b.minY-origin.y)
    }
}

func clampedBoxOrigin(_ origin:CGPoint,size:CGSize,bounds:CGRect) -> CGPoint {
    CGPoint(x:max(bounds.minX,min(origin.x,bounds.maxX-size.width)),
            y:max(bounds.minY,min(origin.y,bounds.maxY-size.height)))
}

func fillAnswerRect(size:CGSize, blank:CGRect, below:CGRect?, selection:CGRect, occupied:[CGRect]) -> CGRect? {
    func usable(_ rect:CGRect) -> Bool {
        selection.contains(rect) && !occupied.contains { $0.insetBy(dx:-2,dy:-2).intersects(rect) }
    }
    let inline = CGRect(origin:blank.origin,size:size)
    if blank.contains(inline) && usable(inline) { return inline }
    let available = below ?? CGRect(x:selection.minX,y:blank.maxY+2,width:selection.width,
                                    height:max(0,selection.maxY-blank.maxY-2))
    let candidate = CGRect(x:max(available.minX,min(blank.minX,available.maxX-size.width)),
                           y:available.minY,width:size.width,height:size.height)
    return available.contains(candidate) && usable(candidate) ? candidate : nil
}
