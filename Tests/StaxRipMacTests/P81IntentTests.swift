import Foundation
import Testing
@testable import StaxRipMac

struct P81IntentTests {
    @Test @MainActor func sourceSpecificIntentVersionsResetAndPresets() throws {
        let source=URL(fileURLWithPath:"/generated/source.mkv")
        var c=EncodeConfiguration();c.selectCodec("Copy original");c.audio="No audio";c.subtitleMode="Remove all subtitles";c.colorMode=DolbyConversionIntent.p81Copy
        c.p81EnhancementLossAcknowledgement=try DolbyLossAcknowledgement(source:source,fingerprint:.init(sha256:String(repeating:"a",count:64),byteCount:123))
        try DolbyConversionIntent.validateCopySettings(c,p81:true)
        #expect(throws:(any Error).self) {try DolbyConversionIntent.requireRunnable(c)}
        let job=QueueJob(id:UUID(),source:source.path,isDemo:false,destination:"/generated/result.mkv",configuration:c,created:Date())
        let session=SessionDocument(sourcePath:source.path,configuration:c,outputFolder:"/generated",outputStem:"result",jobs:[job])
        #expect(try JSONDecoder().decode(SessionDocument.self,from:JSONEncoder().encode(session)).validated()==session)
        var legacy=session;legacy.version=11
        #expect(throws:(any Error).self) {try legacy.validated()}
        var wrong=session;wrong.sourcePath="/generated/other.mkv"
        #expect(throws:(any Error).self) {try wrong.validated()}
        var journal=BatchJournal(jobs:[job],statuses:[:]);_ = try journal.validated();journal.version=10
        #expect(throws:(any Error).self) {try journal.validated()}
        let preset=CustomPreset(name:"P81",configuration:CustomPreset.recipe(c))
        #expect(preset.configuration.p81EnhancementLossAcknowledgement==nil)
        #expect(try preset.applying(to:c).p81EnhancementLossAcknowledgement==nil)
        var library=PresetDocument(presets:[preset]);_ = try library.validated();library.version=3
        #expect(throws:(any Error).self) {try library.validated()}
        let model=WorkspaceModel();model.sourceURL=source;model.config=c;model.sourceURL=URL(fileURLWithPath:"/generated/other.mkv")
        #expect(model.config.p81EnhancementLossAcknowledgement==nil)
        c.colorMode="SDR";#expect(c.p81EnhancementLossAcknowledgement==nil)
    }
}
