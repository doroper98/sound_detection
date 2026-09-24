import Foundation

public enum DiagnosticExport {
    public static func encoder() -> JSONEncoder {
        let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var value=encoder.singleValueContainer(); try value.encode(timestamp(date))
        }
        return encoder
    }
    public static func timestamp(_ date: Date) -> String {
        let formatter=ISO8601DateFormatter()
        formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
        formatter.timeZone=TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
    public static func fileName(date: Date, sessionID: UUID, exportID: UUID) -> String {
        let time=timestamp(date).replacingOccurrences(of: ":",with: "").replacingOccurrences(of: "-",with: "")
        return "SoundField-\(time)-\(sessionID.uuidString.prefix(8))-\(exportID.uuidString).json"
    }
    public static func envelope(_ data: Data, at date: Date, exportID: UUID, historical: Bool) throws -> Data {
        guard var object=try JSONSerialization.jsonObject(with: data) as? [String:Any] else {
            throw CocoaError(.coderInvalidValue)
        }
        object["exportedAt"]=timestamp(date)
        object["exportID"]=exportID.uuidString
        object["historicalReport"]=historical
        return try JSONSerialization.data(withJSONObject: object,options: [.prettyPrinted,.sortedKeys])
    }
}

public struct FOATimelineEntry: Codable, Sendable {
    public let sequence: Int
    public let timestampUTC: String
    public let elapsedSeconds: Double
    public let audioMidpointUptimeSeconds: Double
    public let windowSeconds: Double
    public let acousticState: String
    public let poseIssue: String
    public let displayState: String
    public let bands: [FOABandDiagnostic]
}

public struct FOADiagnosticTimeline: Codable, Sendable {
    public private(set) var history=[FOATimelineEntry]()
    public private(set) var omittedEarlierEntries=0
    public private(set) var acousticStateCounts=[String:Int]()
    public private(set) var failedCheckCounts=[String:Int]()
    public private(set) var firstAudioMidpointUptimeSeconds: Double?
    public let capacity: Int
    public let clockAnchorUTC: String
    public let clockAnchorUptimeSeconds: Double
    public let timeMeaning="UTC derived from session wall-clock/monotonic anchor; elapsedSeconds from first FOA audio midpoint. Bounded recent history; counters cover all processed frames."
    private let anchorDate: Date
    public init(uptime: Double, date: Date, capacity: Int=240) {
        clockAnchorUptimeSeconds=uptime; anchorDate=date; clockAnchorUTC=DiagnosticExport.timestamp(date)
        self.capacity=max(1,capacity)
    }
    public mutating func append(_ analysis: FOAAnalysis, midpoint: Double, duration: Double, poseIssue: String, displayState: String) {
        guard midpoint.isFinite, duration.isFinite, duration>0 else { return }
        if firstAudioMidpointUptimeSeconds == nil { firstAudioMidpointUptimeSeconds=midpoint }
        acousticStateCounts[analysis.state,default: 0]+=1
        for band in analysis.bandDiagnostics {
            for check in band.failedChecks { failedCheckCounts["band\(band.band).\(check)",default: 0]+=1 }
        }
        let sequence=acousticStateCounts.values.reduce(0,+)
        history.append(.init(sequence: sequence,
            timestampUTC: DiagnosticExport.timestamp(anchorDate.addingTimeInterval(midpoint-clockAnchorUptimeSeconds)),
            elapsedSeconds: midpoint-firstAudioMidpointUptimeSeconds!,audioMidpointUptimeSeconds: midpoint,
            windowSeconds: duration,acousticState: analysis.state,poseIssue: poseIssue,displayState: displayState,
            bands: analysis.bandDiagnostics))
        if history.count>capacity { omittedEarlierEntries+=history.count-capacity; history.removeFirst(history.count-capacity) }
    }
}
