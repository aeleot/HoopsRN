import XCTest
@testable import hoopr

/// Holds the in-app legal links (`PRE_LAUNCH_AUDIT.md` §2.3) to the pages
/// they point at. A privacy link that 404s is an App Review rejection, and
/// nothing else would notice a page being renamed out from under the app.
final class LegalLinksTests: XCTestCase {

    func testEveryPageIsHTTPSOnTheProjectsHostingDomain() {
        let expected = [
            (LegalLinks.privacyPolicy, "/privacy"),
            (LegalLinks.termsOfUse, "/terms"),
            (LegalLinks.support, "/support"),
        ]

        for (url, path) in expected {
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "hoopsrn-4f1e9.web.app")
            XCTAssertEqual(url.path, path)
        }
    }

    /// Hosting serves `public/privacy.html` at `/privacy` (`cleanUrls`), so
    /// each link needs a file of that name in the repo.
    func testEveryLinkedPageExistsInTheHostingFolder() throws {
        let publicFolder = Self.repositoryRoot.appendingPathComponent("public")

        for url in [LegalLinks.privacyPolicy, LegalLinks.termsOfUse, LegalLinks.support] {
            let file = publicFolder.appendingPathComponent(url.lastPathComponent + ".html")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: file.path),
                "\(url.absoluteString) has no \(file.lastPathComponent) in public/"
            )
        }
    }

    /// The address in the app and the one on the pages are the same inbox.
    func testThePagesPublishTheSameSupportAddressTheAppMails() throws {
        let publicFolder = Self.repositoryRoot.appendingPathComponent("public")

        for name in ["privacy", "terms", "support"] {
            let html = try String(
                contentsOf: publicFolder.appendingPathComponent(name + ".html"),
                encoding: .utf8
            )
            XCTAssertTrue(html.contains("mailto:" + LegalLinks.supportEmail), "\(name).html")
        }
    }

    func testContactSupportOpensADraftToTheSupportAddressWithASubject() {
        let url = LegalLinks.supportMail

        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertTrue(url.absoluteString.hasPrefix("mailto:" + LegalLinks.supportEmail))
        XCTAssertTrue(url.absoluteString.contains("subject=hoopsRN%20support"))
    }

    func testTheSignUpLineLinksBothDocuments() throws {
        let line = try AttributedString(markdown: LegalLinks.signUpAgreementMarkdown)
        let links = line.runs.compactMap(\.link)

        XCTAssertEqual(links, [LegalLinks.termsOfUse, LegalLinks.privacyPolicy])
        XCTAssertEqual(
            String(line.characters),
            "By creating an account you agree to the Terms of Use and Privacy Policy."
        )
    }

    /// The terms have to say objectionable content isn't tolerated
    /// (Guideline 1.2) — the sentence is the requirement, so hold it.
    func testTheTermsStateZeroToleranceForObjectionableContent() throws {
        let html = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent("public/terms.html"),
            encoding: .utf8
        )
        XCTAssertTrue(html.contains("no tolerance for objectionable content"))
    }

    /// `hooprTests/LegalLinksTests.swift` → the repository root.
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
