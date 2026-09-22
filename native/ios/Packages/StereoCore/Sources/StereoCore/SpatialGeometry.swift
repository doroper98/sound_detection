import Foundation

public struct Vector3: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public static let zero = Vector3(0, 0, 0)
    public static func + (a: Self, b: Self) -> Self { .init(a.x+b.x, a.y+b.y, a.z+b.z) }
    public static func - (a: Self, b: Self) -> Self { .init(a.x-b.x, a.y-b.y, a.z-b.z) }
    public static func * (a: Self, b: Double) -> Self { .init(a.x*b, a.y*b, a.z*b) }
    public func dot(_ b: Self) -> Double { x*b.x + y*b.y + z*b.z }
    public var length: Double { sqrt(dot(self)) }
    public var finite: Bool { x.isFinite && y.isFinite && z.isFinite }
    public func normalized() -> Self { length > 1e-12 ? self * (1 / length) : .zero }
    public func angle(to b: Self) -> Double { acos(max(-1, min(1, normalized().dot(b.normalized())))) * 180 / .pi }
}

/// Axes are the portrait VIEW axes: right, up and forward into the camera image.
/// They are not ARCamera.transform's fixed sensor axes.
public struct SpatialPose: Codable, Sendable {
    public let time: Double
    public let origin: Vector3
    public let right: Vector3
    public let up: Vector3
    public let forward: Vector3
    public init(time: Double, origin: Vector3, right: Vector3, up: Vector3, forward: Vector3) {
        self.time = time; self.origin = origin; self.right = right; self.up = up; self.forward = forward
    }
    public var valid: Bool {
        time.isFinite && origin.finite && [right, up, forward].allSatisfy { $0.finite && abs($0.length-1) < 0.01 }
            && abs(right.dot(up)) < 0.01 && abs(right.dot(forward)) < 0.01 && abs(up.dot(forward)) < 0.01
    }
    public func bearing(of direction: Vector3) -> Double { atan2(direction.dot(right), direction.dot(forward)) * 180 / .pi }
    public func elevation(of direction: Vector3) -> Double {
        atan2(direction.dot(up), hypot(direction.dot(right), direction.dot(forward))) * 180 / .pi
    }
}

public struct SpatialPoseHistory {
    private var poses: [SpatialPose] = []
    public init() {}
    public mutating func append(_ pose: SpatialPose) {
        guard pose.valid, poses.last.map({ pose.time > $0.time }) ?? true else { return }
        poses.append(pose)
        poses.removeAll { pose.time-$0.time > 2 }
        if poses.count > 150 { poses.removeFirst(poses.count-150) }
    }
    public func nearest(_ time: Double) -> SpatialPose? {
        guard time.isFinite, let p = poses.min(by: { abs($0.time-time) < abs($1.time-time) }), abs(p.time-time) <= 0.06 else { return nil }
        return p
    }
    public func aligned(midpoint: Double, duration: Double) -> SpatialPose? {
        guard duration.isFinite, duration > 0, duration <= 0.4,
              let a = nearest(midpoint-duration/2), let b = nearest(midpoint+duration/2), let middle = nearest(midpoint),
              (a.origin-b.origin).length <= 0.025, a.forward.angle(to: b.forward) <= 3,
              a.right.angle(to: b.right) <= 3 else { return nil }
        return middle
    }
}

public struct BearingObservation: Codable, Sendable {
    public let pose: SpatialPose
    public let angleDegrees: Double
    public let uncertaintyDegrees: Double
    public init(pose: SpatialPose, angleDegrees: Double, uncertaintyDegrees: Double) {
        self.pose = pose; self.angleDegrees = angleDegrees; self.uncertaintyDegrees = uncertaintyDegrees
    }
    var normal: Vector3 {
        let a = angleDegrees * .pi / 180
        return pose.right * cos(a) - pose.forward * sin(a)
    }
}

public struct SpatialEstimate: Codable, Sendable {
    public let point: Vector3
    public let uncertaintyRadiusMeters: Double
    public let residualDegrees: Double
    public let independentPoses: Int
    public let baselineMeters: Double
    public let time: Double
}

public struct SpatialSolution: Codable, Sendable {
    public let state: String
    public let observationCount: Int
    public let estimate: SpatialEstimate?
}

/// Intersections of horizontal bearing PLANES, not invented full bearing rays.
/// A level phone cannot resolve source height. Rotations without translation
/// cannot resolve range. No source/reference coordinates enter this solver.
public struct SpatialAccumulator {
    private var rows: [BearingObservation] = []
    private var lastInputTime: Double?
    public init() {}
    public mutating func append(_ row: BearingObservation) {
        guard row.pose.valid, row.angleDegrees.isFinite, abs(row.angleDegrees) <= 30,
              row.uncertaintyDegrees.isFinite, (2...12).contains(row.uncertaintyDegrees),
              lastInputTime.map({ row.pose.time > $0 }) ?? true else { return }
        if let last = lastInputTime, row.pose.time-last > 1 { rows = [] }
        lastInputTime = row.pose.time
        rows.removeAll { row.pose.time-$0.pose.time > 12 }
        // Repeated frames at one pose never add independent geometric evidence.
        guard !rows.contains(where: { (row.pose.origin-$0.pose.origin).length < 0.08
            && row.pose.right.angle(to: $0.pose.right) < 8 && row.pose.forward.angle(to: $0.pose.forward) < 8 }) else { return }
        rows.append(row)
        if rows.count > 60 { rows.removeFirst() }
    }
    public mutating func reset() { rows = []; lastInputTime = nil }
    public func solve(at now: Double) -> SpatialSolution {
        func result(_ state: String, _ e: SpatialEstimate? = nil) -> SpatialSolution {
            .init(state: state, observationCount: rows.count, estimate: e)
        }
        guard let last = lastInputTime, now-last >= -0.06, now-last < 0.5 else { return result("stale") }
        guard rows.count >= 8 else { return result("needMorePoses") }
        let baseline = rows.map { a in rows.map { (a.pose.origin-$0.pose.origin).length }.max() ?? 0 }.max() ?? 0
        guard baseline >= 0.3 else { return result("needTranslation") }
        var weights = rows.map { 1 / pow($0.uncertaintyDegrees * .pi / 180, 2) }
        var point = Vector3.zero, inverse = [Double](repeating: 0, count: 9)
        for iteration in 0..<4 {
            var matrix = [Double](repeating: 0, count: 9), rhs = Vector3.zero
            for (index, row) in rows.enumerated() {
                let n = row.normal, w = weights[index], v = [n.x, n.y, n.z]
                for i in 0..<3 { for j in 0..<3 { matrix[i*3+j] += w*v[i]*v[j] } }
                rhs = rhs + n * (w*n.dot(row.pose.origin))
            }
            let eigen = eigenvalues(matrix)
            guard let smallest = eigen.min(), let largest = eigen.max(), smallest > largest * 0.015 else { return result("needTiltOrParallax") }
            guard let inv = invert(matrix) else { return result("needTiltOrParallax") }
            inverse = inv
            point = multiply(inv, rhs)
            guard point.finite else { return result("inconsistent") }
            if iteration < 3 {
                weights = rows.map { row in
                    let distance = max(0.3, (point-row.pose.origin).length)
                    return 1 / pow(distance * row.uncertaintyDegrees * .pi / 180, 2)
                }
            }
        }
        let errors = rows.map { abs($0.pose.bearing(of: point-$0.pose.origin)-$0.angleDegrees) }
        let rms = sqrt(errors.reduce(0) { $0+$1*$1 } / Double(errors.count))
        guard rms <= 6, (errors.max() ?? 100) <= 15 else { return result("inconsistent") }
        guard rows.allSatisfy({ row in
            let delta = point-row.pose.origin
            return (0.4...8).contains(delta.length) && delta.dot(row.pose.forward) > 0
                && abs(row.pose.elevation(of: delta)) < 30
        }) else { return result("outOfRange") }
        // Conservative model sensitivity, NOT a validated physical confidence interval.
        let radius = 2 * sqrt(max(0, eigenvalues(inverse).max() ?? .infinity))
        guard radius.isFinite, radius <= 1, radius < (point-rows.last!.pose.origin).length * 0.5 else { return result("uncertain") }
        return result("candidate", SpatialEstimate(point: point, uncertaintyRadiusMeters: radius,
            residualDegrees: rms, independentPoses: rows.count, baselineMeters: baseline, time: last))
    }
}

private func multiply(_ m: [Double], _ v: Vector3) -> Vector3 {
    .init(m[0]*v.x+m[1]*v.y+m[2]*v.z, m[3]*v.x+m[4]*v.y+m[5]*v.z, m[6]*v.x+m[7]*v.y+m[8]*v.z)
}
private func invert(_ m: [Double]) -> [Double]? {
    let a=m[0], b=m[1], c=m[2], d=m[3], e=m[4], f=m[5], g=m[6], h=m[7], i=m[8]
    let det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
    guard det.isFinite, abs(det)>1e-12 else { return nil }
    return [e*i-f*h,c*h-b*i,b*f-c*e,f*g-d*i,a*i-c*g,c*d-a*f,d*h-e*g,b*g-a*h,a*e-b*d].map { $0/det }
}
private func eigenvalues(_ values: [Double]) -> [Double] {
    var a = values
    for _ in 0..<24 {
        let pair = [(0,1),(0,2),(1,2)].max { abs(a[$0.0*3+$0.1]) < abs(a[$1.0*3+$1.1]) }!
        let p=pair.0, q=pair.1, apq=a[p*3+q]
        if abs(apq)<1e-12 { break }
        let angle=0.5*atan2(2*apq, a[q*3+q]-a[p*3+p]), c=cos(angle), s=sin(angle)
        let app=a[p*3+p], aqq=a[q*3+q]
        for k in 0..<3 where k != p && k != q {
            let kp=a[k*3+p], kq=a[k*3+q]
            a[k*3+p]=c*kp-s*kq; a[p*3+k]=a[k*3+p]
            a[k*3+q]=s*kp+c*kq; a[q*3+k]=a[k*3+q]
        }
        a[p*3+p]=c*c*app-2*s*c*apq+s*s*aqq
        a[q*3+q]=s*s*app+2*s*c*apq+c*c*aqq
        a[p*3+q]=0; a[q*3+p]=0
    }
    return [a[0],a[4],a[8]]
}
