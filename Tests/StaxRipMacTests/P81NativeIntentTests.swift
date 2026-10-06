import Foundation
import Testing
@testable import StaxRipMac

struct P81NativeIntentTests {
    @Test func ordinaryPreflightDefersCompleteVerificationAndGenericPlanStillRefuses() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("p81-intent-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
        let source=root.appendingPathComponent("generated.mkv")
        try Data([0]).write(to:source,options:.withoutOverwriting)
        var c=EncodeConfiguration();c.selectCodec("Copy original");c.audio="No audio";c.subtitleMode="Remove all subtitles";c.colorMode=DolbyConversionIntent.p81Copy
        c.p81EnhancementLossAcknowledgement=try DolbyLossAcknowledgement(source:source,fingerprint:.init(sha256:String(repeating:"a",count:64),byteCount:1))
        let job=QueueJob(id:UUID(),source:source.path,isDemo:false,destination:root.appendingPathComponent("result.mkv").path,configuration:c,created:Date())
        let tools=try #require(FFmpegTools.discover())
        #expect(throws:(any Error).self) {try DolbyConversionIntent.requireRunnable(c)}
        let result=try await QueuePreflight.inspect(job,tools:tools,encoders:[])
        #expect(result.kind == .deferred)
        #expect(!FileManager.default.fileExists(atPath:job.destination))
        let copying=QueueJobPresentation(job:job,status:.init(phase:"Encoding"),publishing:false,check:nil)
        #expect(copying.label == "Copying")
        let complete=QueueJobPresentation(job:job,status:.init(phase:"Completed",detail:"Verified result"),publishing:false,check:nil)
        #expect(complete.showStatusDetail)
        // Retain the generated root; this preflight has no publication or cleanup authority.
    }
}
