import Foundation
import StereoCore

func fixture(root: URL) throws -> URL {
    let labels = ResearchLabels(label: "synthetic-replay-contract", azimuthDegrees: 0, elevationDegrees: 0,
                                signal: "other", repetition: 1)
    let writer = try ResearchSessionWriter(root: root, sampleRate: 48000, labels: labels,
        appVersion: "fixture", buildNumber: "fixture", deviceModel: "synthetic", operatingSystem: "host",
        synthetic: true, saveStereo: true)
    var assembler = PCMWindowAssembler(channels: 4)
    for frame in 0...33 {
        let pose = ResearchPoseSample(timestamp: 100 + Double(frame) / 30,
            quaternion: [0,0,0,1], position: .zero, viewRight: .init(1,0,0),
            viewUp: .init(0,1,0), viewForward: .init(0,0,-1), trackingState: "normal")
        try writer.appendPose(pose)
    }
    for start in stride(from: 0, to: 48000, by: 1024) {
        let count = min(1024,48000 - start)
        let wave: [Float] = (start..<(start + count)).map { index in
            let phase = Double(index) * 2.0 * Double.pi / 48000.0
            return Float(0.05 * (sin(phase * 750.0) + sin(phase * 1500.0)))
        }
        let zero = [Float](repeating: 0, count: count)
        let pcm = [wave,zero,zero,wave]
        let time = 100 + Double(start) / 48000
        try writer.appendAudio(pcm, at: time)
        try writer.appendAudio([wave,wave], at: time, stereo: true)
        for window in assembler.append(pcm, at: time, sampleRate: 48000) {
            let duration = Double(window.channels[0].count) / 48000
            try writer.appendAnalysis(.init(midpointHostSeconds: window.start + duration / 2,
                durationSeconds: duration, analysis: FOAAnalyzer.analyze(window.channels, sampleRate: 48000)))
        }
    }
    _ = try writer.finish(reason: "synthetic fixture")
    return writer.folder
}

do {
    var arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "--fixture", arguments.count == 2 {
        print(try fixture(root: URL(fileURLWithPath: arguments[1], isDirectory: true)).path)
    } else {
        var output: String?
        if let index = arguments.firstIndex(of: "--output"), index + 1 < arguments.count {
            output = arguments[index + 1]
            arguments.removeSubrange(index...(index + 1))
        }
        guard arguments.count == 1 else {
            throw ResearchError.invalid("사용법: foa-replay <세션 폴더> [--output 결과.json] 또는 --fixture <합성 폴더>")
        }
        let result = try ResearchReplay.run(folder: URL(fileURLWithPath: arguments[0], isDirectory: true))
        let data = try DiagnosticExport.encoder().encode(result)
        if let output { try data.write(to: URL(fileURLWithPath: output), options: .atomic) }
        else {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
        }
        guard result.mismatchedWindows == 0, result.unmatchedLiveWindows == 0 else {
            throw ResearchError.invalid("실시간/재생 결과가 다릅니다. 결과 JSON을 확인하세요.")
        }
    }
} catch {
    FileHandle.standardError.write(Data("foa-replay: \(error.localizedDescription)\n".utf8))
    exit(1)
}
