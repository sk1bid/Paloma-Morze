import Foundation
import Testing
@testable import PalomaMorse

struct UpdateConfigurationTests {
    @Test func onlyConfiguredHTTPSFeedsAreEnabled() {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        #expect(UpdateConfiguration.isValid(["SUFeedURL":"https://example.org/native/appcast.xml", "SUPublicEDKey":key]))
        for url in ["", "http://example.org/feed", "file:///tmp/feed", "https://user:pass@example.org/feed"] {
            #expect(!UpdateConfiguration.isValid(["SUFeedURL":url,"SUPublicEDKey":key]))
        }
        #expect(!UpdateConfiguration.isValid(["SUFeedURL":"https://example.org/feed","SUPublicEDKey":"missing"]))
        #expect(!UpdateConfiguration.isValid([:]))
    }
}
