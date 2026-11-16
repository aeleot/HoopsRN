import Foundation

/// Where the app's legal pages and its support contact live (App Review
/// Guidelines 5.1.1(i) and 1.2).
///
/// One source for all of them: the same three pages are linked from Profile,
/// from the sign-up form and from App Store Connect, and a privacy link that
/// 404s is a rejection. The pages themselves are `public/` in this repo,
/// served by Firebase Hosting on the project's own domain — so these paths and
/// the files there have to move together (`LegalLinksTests` holds them to it).
enum LegalLinks {
    static let host = "hoopsrn-4f1e9.web.app"

    static let privacyPolicy = page("privacy")
    static let termsOfUse = page("terms")
    static let support = page("support")

    /// Published on the support page too, so it is not a secret — but it is
    /// one person's inbox, and the first thing to change when there is a
    /// domain to put a support address on.
    static let supportEmail = "chaseallen122@gmail.com"

    /// Opens a draft in Mail with the subject filled in, so a message arrives
    /// saying which app it is about.
    static let supportMail: URL = {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: "hoopsRN support")]
        return components.url ?? support
    }()

    /// The sentence under the sign-up button, with both documents linked.
    /// Markdown, because `Text` turns it into tappable links that VoiceOver
    /// reads as links — two buttons in a sentence would not wrap as one.
    static let signUpAgreementMarkdown =
        "By creating an account you agree to the [Terms of Use](\(termsOfUse.absoluteString)) "
        + "and [Privacy Policy](\(privacyPolicy.absoluteString))."

    private static func page(_ path: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/" + path
        // The parts are constants above; this cannot fail for them.
        return components.url!
    }
}
