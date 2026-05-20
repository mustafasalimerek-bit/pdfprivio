import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    /// Universal Link host. Must match Runner.entitlements'
    /// applinks: domain and the AASA file deployed to that domain.
    private let universalLinkHost = "privio-aasa.netlify.app"

    // Cold-launch URL or Universal Link. iOS hands either kind of
    // wake-up signal here on the very first scene attachment.
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        // Custom URL scheme (pdfprivio://) — legacy fallback path.
        for context in connectionOptions.urlContexts {
            handleWakeUpURL(context.url)
        }
        // Universal Link — the modern iOS-17+ wake-up that share/action
        // extensions use, since custom schemes are blocked there.
        for activity in connectionOptions.userActivities {
            handleUserActivity(activity)
        }
    }

    // Warm-launch URL — extension fired pdfprivio:// while Privio was
    // already in memory. In scene mode iOS routes URLs to SceneDelegate
    // (NOT AppDelegate.application(_:open:)).
    override func scene(
        _ scene: UIScene,
        openURLContexts URLContexts: Set<UIOpenURLContext>
    ) {
        super.scene(scene, openURLContexts: URLContexts)
        for context in URLContexts {
            handleWakeUpURL(context.url)
        }
    }

    // Warm-launch Universal Link — extension fired an HTTPS URL on our
    // applinks domain while Privio was running. iOS hands us a
    // NSUserActivityTypeBrowsingWeb whose webpageURL is the URL fired.
    override func scene(
        _ scene: UIScene,
        continue userActivity: NSUserActivity
    ) {
        super.scene(scene, continue: userActivity)
        handleUserActivity(userActivity)
    }

    // MARK: - Routing

    private func handleUserActivity(_ activity: NSUserActivity) {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = activity.webpageURL else { return }
        handleWakeUpURL(url)
    }

    /// Both Universal Links and the legacy custom scheme funnel into
    /// the same logic: tell the share-extension bridge a drop is
    /// pending so Flutter's lifecycle observer picks the file up off
    /// the App Group folder and routes to the right tool.
    private func handleWakeUpURL(_ url: URL) {
        let isUniversalLink = url.scheme == "https"
            && url.host == universalLinkHost
        let isCustomScheme = url.scheme == "pdfprivio"
        guard isUniversalLink || isCustomScheme else { return }
        ShareExtensionBridge.notifyNewShare()
    }
}
