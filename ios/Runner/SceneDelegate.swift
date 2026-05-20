import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    // Cold-launch URL — if the app starts as a result of a
    // `pdfprivio://` URL fired by one of our share extensions, the URL
    // arrives in `connectionOptions.URLContexts` rather than through
    // `scene(_:openURLContexts:)`.
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        for context in connectionOptions.urlContexts {
            handlePrivioURL(context.url)
        }
    }

    // Warm-launch URL — the extension fired `pdfprivio://share` while
    // Privio was already in memory. In scene mode iOS routes the URL to
    // SceneDelegate, NOT AppDelegate.application(_:open:options:), so
    // without this override the wake-up signal would be dropped and the
    // user would see Privio in the foreground with no action sheet.
    override func scene(
        _ scene: UIScene,
        openURLContexts URLContexts: Set<UIOpenURLContext>
    ) {
        super.scene(scene, openURLContexts: URLContexts)
        for context in URLContexts {
            handlePrivioURL(context.url)
        }
    }

    private func handlePrivioURL(_ url: URL) {
        guard url.scheme == "pdfprivio" else { return }
        ShareExtensionBridge.notifyNewShare()
    }
}
