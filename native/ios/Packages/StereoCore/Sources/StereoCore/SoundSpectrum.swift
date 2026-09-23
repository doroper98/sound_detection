import Foundation

/// Bounded statistics from the current stereo buffer, never audio or an image.
/// Powers are combined after each channel's FFT so opposite phases cannot cancel.
public struct SoundSpectrum: Codable, Sendable {
    public let levelDbfs: Double
    public let dominantHz: Double?
    public let lowerHz: Double
    public let upperHz: Double
    public let binWidthHz: Double
    public let fftSize: Int
    public let peakPowerFraction: Double

    public var frequencyLabel: String {
        if let dominantHz { return "주파수 ≈ " + Self.hertz(dominantHz) }
        if lowerHz>=1000 { return String(format: "대역 %.1f–%.1f kHz",lowerHz/1000,upperHz/1000) }
        if upperHz<1000 { return String(format: "대역 %.0f–%.0f Hz",lowerHz,upperHz) }
        return "대역 " + Self.hertz(lowerHz) + "–" + Self.hertz(upperHz)
    }
    private static func hertz(_ value: Double) -> String {
        value >= 1000 ? String(format: "%.1f kHz",value/1000) : String(format: "%.0f Hz",value)
    }
}

/// Fixed receiver-level scale. Not SPL, source sound power, or confidence.
public enum SoundHeatLevel {
    public static func normalized(_ dbfs: Double) -> Double {
        guard dbfs.isFinite else { return 0 }
        return min(1,max(0,(dbfs+65)/50))
    }
}

public enum SoundSpectrumAnalyzer {
    public static func measure(left: [Float], right: [Float], sampleRate: Double) -> SoundSpectrum? {
        guard left.count==right.count, (1024...16384).contains(left.count),
              sampleRate.isFinite, (8000...192000).contains(sampleRate),
              left.allSatisfy({ $0.isFinite && abs($0)<0.999 }),
              right.allSatisfy({ $0.isFinite && abs($0)<0.999 }) else { return nil }
        var n=1024
        while n*2<=min(4096,left.count) { n*=2 }
        // Center the FFT on the same buffer midpoint used for the AR pose.
        let offset=(left.count-n)/2, width=sampleRate/Double(n)
        var power=[Double](repeating: 0,count: n/2+1)
        var totalMeanSquare=0.0
        for channel in [left,right] {
            let samples=channel[offset..<offset+n].map(Double.init)
            let mean=samples.reduce(0,+)/Double(n)
            var real=[Double](repeating: 0,count: n), imaginary=real
            var windowEnergy=0.0
            for i in 0..<n {
                let centered=samples[i]-mean, window=0.5-0.5*cos(2 * .pi*Double(i)/Double(n))
                real[i]=centered*window
                windowEnergy+=window*window
                totalMeanSquare+=centered*centered/Double(n*2)
            }
            fft(real: &real,imaginary: &imaginary)
            for k in 0...n/2 {
                let factor=(k==0 || k==n/2) ? 1.0 : 2.0
                power[k]+=(real[k]*real[k]+imaginary[k]*imaginary[k])*factor/(Double(n)*windowEnergy*2)
            }
        }
        guard totalMeanSquare>1e-8 else { return nil }
        let first=max(1,Int(ceil(80/width))), last=min(n/2,Int(floor(16000/width)))
        guard first<last else { return nil }
        let sum=power[first...last].reduce(0,+)
        guard sum>1e-8, let peak=(first...last).max(by: { power[$0]<power[$1] }) else { return nil }
        let fraction=power[max(first,peak-1)...min(last,peak+1)].reduce(0,+)/sum
        var cumulative=0.0, low=first, high=last, lowFound=false
        for k in first...last {
            cumulative+=power[k]
            if !lowFound && cumulative>=sum*0.1 { low=k; lowFound=true }
            if cumulative>=sum*0.9 { high=k; break }
        }
        // A broad/noisy spectrum gets an 80%-energy band, not a random peak label.
        return SoundSpectrum(levelDbfs: 10*log10(totalMeanSquare),
            dominantHz: fraction>=0.12 ? Double(peak)*width : nil,
            lowerHz: Double(low)*width,upperHz: Double(high)*width,binWidthHz: width,
            fftSize: n,peakPowerFraction: fraction)
    }

    static func fft(real: inout [Double], imaginary: inout [Double]) {
        let n=real.count
        var j=0
        for i in 1..<n {
            var bit=n>>1
            while j&bit != 0 { j ^= bit; bit >>= 1 }
            j ^= bit
            if i<j { real.swapAt(i,j); imaginary.swapAt(i,j) }
        }
        var length=2
        while length<=n {
            let angle = -2 * Double.pi/Double(length), stepR=cos(angle), stepI=sin(angle)
            for start in stride(from: 0,to: n,by: length) {
                var wr=1.0, wi=0.0
                for k in 0..<length/2 {
                    let a=start+k, b=a+length/2
                    let tr=wr*real[b]-wi*imaginary[b], ti=wr*imaginary[b]+wi*real[b]
                    real[b]=real[a]-tr; imaginary[b]=imaginary[a]-ti
                    real[a]+=tr; imaginary[a]+=ti
                    let nextR=wr*stepR-wi*stepI
                    wi=wr*stepI+wi*stepR; wr=nextR
                }
            }
            length*=2
        }
    }
}
