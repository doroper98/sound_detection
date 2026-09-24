import Foundation

/// ACN/SN3D W,Y,Z,X. Directions are in the encoded sound field, not device coordinates.
public struct FOARegion: Codable, Sendable {
    public let band: Int
    public let direction: Vector3
    public let lowerHz: Double
    public let upperHz: Double
    public let dominantHz: Double?
    public let levelDbfs: Double
    public let coherence: Double
    public let energyBalance: Double
    public let spreadDegrees: Double
    public var frequencyLabel: String {
        if let hz=dominantHz { return hz<1000 ? String(format: "%.0f Hz",hz) : String(format: "%.1f kHz",hz/1000) }
        return String(format: "%.0f–%.0f Hz",lowerHz,upperHz)
    }
}

public struct FOAAnalysis: Codable, Sendable {
    public let state: String
    public let regions: [FOARegion]
    public let channelRMS: [Double]
    public let sampleRate: Double
    public let samples: Int
    public let rejectedBands: Int
    public let bandDiagnostics: [FOABandDiagnostic]
    public let physicalAccuracyVerified = false
}

public struct FOABandDiagnostic: Codable, Sendable {
    public let band: Int
    public let lowerHz: Double
    public let upperHz: Double
    public var state: String
    public var levelDbfs: Double?
    public var directionalToOmniEnergy: Double?
    public var coherence: Double?
    public var energyBalance: Double?
    public var spreadDegrees: Double?
    public var direction: Vector3?
}

public enum FOAAnalyzer {
    public static func analyze(_ channels: [[Float]], sampleRate: Double) -> FOAAnalysis {
        let n=4096
        var diagnostics=[FOABandDiagnostic]()
        func result(_ state: String, _ regions: [FOARegion]=[], _ rms: [Double]=[], _ rejected: Int=0) -> FOAAnalysis {
            .init(state: state,regions: regions,channelRMS: rms,sampleRate: sampleRate.isFinite ? sampleRate : 0,
                  samples: channels.first?.count ?? 0,rejectedBands: rejected,bandDiagnostics: diagnostics)
        }
        guard channels.count==4, channels.allSatisfy({ $0.count==n }),
              sampleRate.isFinite, (32000...96000).contains(sampleRate),
              channels.allSatisfy({ $0.allSatisfy(\.isFinite) }) else { return result("invalidPCM") }
        guard !channels.contains(where: { $0.contains(where: { abs($0)>=0.999 }) }) else { return result("clipped") }
        let rms=channels.map { sqrt($0.reduce(0.0) { $0+Double($1)*Double($1) }/Double(n)) }
        var reals=[[Double]](), imaginaries=[[Double]](), windowEnergy=0.0
        let window=(0..<n).map { 0.5-0.5*cos(2 * .pi*Double($0)/Double(n)) }
        windowEnergy=window.reduce(0) { $0+$1*$1 }
        for channel in channels {
            let mean=channel.reduce(0.0) { $0+Double($1) }/Double(n)
            var r=(0..<n).map { (Double(channel[$0])-mean)*window[$0] }
            var im=[Double](repeating: 0,count: n)
            SoundSpectrumAnalyzer.fft(real: &r,imaginary: &im)
            reals.append(r); imaginaries.append(im)
        }
        let width=sampleRate/Double(n), scale=2/(Double(n)*windowEnergy)
        let ranges=[(160.0,600.0),(600.0,2000.0),(2000.0,8000.0)]
        var regions=[FOARegion](), rejected=0, anyEnergy=false
        for (band,range) in ranges.enumerated() {
            let bins=Int(ceil(range.0/width))..<min(n/2,Int(ceil(range.1/width)))
            var cross=Vector3.zero, p=0.0, v=0.0, powers=[(Int,Double)](), vectors=[(Vector3,Double)]()
            for k in bins {
                let pw=reals[0][k]*reals[0][k]+imaginaries[0][k]*imaginaries[0][k]
                func component(_ c: Int) -> Double { reals[0][k]*reals[c][k]+imaginaries[0][k]*imaginaries[c][k] }
                let vector=Vector3(component(3),component(1),component(2))
                cross=cross+vector; p+=pw
                for c in 1...3 { v+=reals[c][k]*reals[c][k]+imaginaries[c][k]*imaginaries[c][k] }
                powers.append((k,pw)); vectors.append((vector,pw))
            }
            var diagnostic=FOABandDiagnostic(band: band,lowerHz: range.0,upperHz: range.1,state: "quiet")
            if p>0 { diagnostic.levelDbfs=10*log10(p*scale); diagnostic.directionalToOmniEnergy=v/p }
            defer { diagnostics.append(diagnostic) }
            guard p*scale>pow(10,-65.0/10) else { rejected+=1; continue }
            anyEnergy=true
            diagnostic.state="noDirectionalVector"
            guard v>1e-12, cross.length>1e-9*p else { rejected+=1; continue }
            let coherence=min(1,cross.length/sqrt(p*v)), balance=2*cross.length/(p+v)
            let direction=cross.normalized(), ratio=v/p
            diagnostic.coherence=coherence; diagnostic.energyBalance=balance; diagnostic.direction=direction
            diagnostic.state="inconsistentComponents"
            // Heuristics only. Even coherent reflections may pass; never a calibrated confidence.
            guard coherence>=0.7, balance>=0.65, (0.25...1.8).contains(ratio) else { rejected+=1; continue }
            let spread=sqrt(vectors.reduce(0.0) { sum,row in
                guard row.1>p*0.0001, row.0.length>1e-12 else { return sum }
                return sum+row.1*pow(row.0.angle(to: direction),2)
            }/p)
            diagnostic.spreadDegrees=spread; diagnostic.state="angularSpread"
            guard spread<35 else { rejected+=1; continue }
            diagnostic.state="candidate"
            let peak=powers.max(by: { $0.1<$1.1 })!
            let peakPower=powers.filter { abs($0.0-peak.0)<=1 }.reduce(0) { $0+$1.1 }
            regions.append(.init(band: band,direction: direction,lowerHz: range.0,upperHz: range.1,
                dominantHz: peakPower/p>=0.15 ? Double(peak.0)*width : nil,
                levelDbfs: 10*log10(p*scale),coherence: coherence,energyBalance: balance,spreadDegrees: spread))
        }
        return result(regions.isEmpty ? (anyEnergy ? "ambiguous" : "quiet") : "candidate",regions,rms,rejected)
    }
}

public struct PCMWindow: Sendable {
    public let channels: [[Float]]
    public let start: Double
    public let sampleRate: Double
}

/// Bounded accumulation, independent of the device callback's buffer size.
public struct PCMWindowAssembler {
    private let channelCount: Int
    private let windowSize: Int
    private var channels: [[Float]]
    private var start: Double?
    private var rate: Double?
    public private(set) var gaps=0
    public init(channels: Int, size: Int=4096) {
        channelCount=channels; windowSize=size; self.channels=Array(repeating: [],count: channels)
    }
    public mutating func append(_ input: [[Float]], at time: Double, sampleRate: Double) -> [PCMWindow] {
        guard time.isFinite, time>=0, sampleRate.isFinite, (8000...192000).contains(sampleRate),
              input.count==channelCount, let count=input.first?.count, (1...16384).contains(count),
              input.allSatisfy({ $0.count==count && $0.allSatisfy(\.isFinite) }) else {
            channels=Array(repeating: [],count: channelCount); start=nil; rate=nil; gaps+=1; return []
        }
        if let start, let rate,
           rate != sampleRate || abs(time-(start+Double(channels[0].count)/rate))>max(2/rate,0.002) {
            channels=Array(repeating: [],count: channelCount); self.start=nil; gaps+=1
        }
        if start == nil { start=time }
        rate=sampleRate
        for c in 0..<channelCount { channels[c].append(contentsOf: input[c]) }
        var result=[PCMWindow]()
        while channels[0].count>=windowSize {
            result.append(.init(channels: channels.map { Array($0.prefix(windowSize)) },start: start!,sampleRate: sampleRate))
            for c in 0..<channelCount { channels[c].removeFirst(windowSize) }
            start! += Double(windowSize)/sampleRate
        }
        return result
    }
}
