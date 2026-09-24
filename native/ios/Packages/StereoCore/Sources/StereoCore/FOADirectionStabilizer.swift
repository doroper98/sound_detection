import Foundation

public struct FOATrackedRegion: Sendable {
    public let acoustic: FOARegion
    public let worldDirection: Vector3
    public let lastObserved: Double
    public let observations: Int
    public let recentOnly: Bool
}

/// Presentation evidence only. Does not turn rejected acoustic frames into estimates.
public struct FOADirectionStabilizer {
    public static let confirmations=3
    public static let maximumDirectionChangeDegrees=18.0
    public static let maximumObservationGap=0.15
    public static let maximumHoldSeconds=0.28
    public static let maximumAgeSeconds=0.30
    private struct Track {
        var acoustic: FOARegion
        var direction: Vector3
        var at: Double
        var count: Int
        var confirmed: Bool
        var recentOnly=false
    }
    private var tracks=[Int:Track]()
    public private(set) var regions=[FOATrackedRegion]()
    public private(set) var state="waiting"
    private var lastInput: Double?
    public init() {}
    public mutating func clear(state: String) {
        tracks=[:]; regions=[]; self.state=state; lastInput=nil
    }
    public mutating func observe(_ analysis: FOAAnalysis, pose: SpatialPose, at time: Double, now: Double) {
        guard time.isFinite, now.isFinite, time<=now+0.06, now-time<Self.maximumAgeSeconds, pose.valid else {
            clear(state: "stale"); return
        }
        if let last=lastInput, time<=last { clear(state: "invalidTiming"); return }
        lastInput=time
        guard analysis.state == "candidate" || analysis.state == "ambiguous" else {
            clear(state: analysis.state); return
        }
        let current=Set(analysis.regions.map(\.band))
        for band in Array(tracks.keys) where !current.contains(band) {
            guard var track=tracks[band], track.confirmed, time-track.at<=Self.maximumHoldSeconds else {
                tracks.removeValue(forKey: band); continue
            }
            // Quiet or missing bands do not hold a previous frequency/level as current.
            guard let diagnostic=analysis.bandDiagnostics.first(where: { $0.band==band }),
                  diagnostic.state != "quiet", diagnostic.state != "noDirectionalVector" else {
                tracks.removeValue(forKey: band); continue
            }
            track.recentOnly=true; tracks[band]=track
        }
        for region in analysis.regions {
            let d=region.direction
            let world=(pose.forward*d.x-pose.right*d.y+pose.up*d.z).normalized()
            if var track=tracks[region.band], time-track.at<=(track.confirmed ? Self.maximumHoldSeconds : Self.maximumObservationGap),
               track.direction.angle(to: world)<=Self.maximumDirectionChangeDegrees {
                // Only blend nearby, accepted world directions. Never bridge a direction jump.
                track.direction=(track.direction*0.6+world*0.4).normalized()
                track.acoustic=region; track.at=time; track.count=min(1000,track.count+1)
                track.confirmed=track.confirmed || track.count>=Self.confirmations
                track.recentOnly=false; tracks[region.band]=track
            } else {
                tracks[region.band]=Track(acoustic: region,direction: world,at: time,count: 1,confirmed: false)
            }
        }
        state=analysis.state
        refresh(at: now)
    }
    public mutating func refresh(at now: Double) {
        guard now.isFinite else { clear(state: "invalidTiming"); return }
        for band in Array(tracks.keys) {
            guard let track=tracks[band] else { continue }
            if now-track.at>=Self.maximumAgeSeconds || (track.recentOnly && now-track.at>=Self.maximumHoldSeconds) {
                tracks.removeValue(forKey: band)
            }
        }
        regions=tracks.values.filter(\.confirmed).sorted { $0.acoustic.band<$1.acoustic.band }.map {
            .init(acoustic: $0.acoustic,worldDirection: $0.direction,lastObserved: $0.at,
                  observations: $0.count,recentOnly: $0.recentOnly)
        }
        if !regions.isEmpty { state=regions.contains(where: \.recentOnly) ? "rechecking" : "candidate" }
        else if !tracks.isEmpty { state="confirming" }
        else if state == "candidate" || state == "rechecking" || state == "confirming" { state="stale" }
    }
}
