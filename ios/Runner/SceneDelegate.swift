//
//  SceneDelegate.swift
//  Runner
//
//  Required by flutter_carplay plugin
//

import UIKit
import Flutter

@available(iOS 13.0, *)
@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        window = UIWindow(windowScene: windowScene)

        let controller = FlutterViewController.init(engine: flutterEngine, nibName: nil, bundle: nil)
        controller.loadDefaultSplashScreenView()
        window?.rootViewController = controller
        window?.makeKeyAndVisible()

        if let url = connectionOptions.urlContexts.first?.url {
            _ = (UIApplication.shared.delegate as? FlutterAppDelegate)?.application(
                UIApplication.shared,
                open: url,
                options: [:]
            )
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            _ = (UIApplication.shared.delegate as? FlutterAppDelegate)?.application(
                UIApplication.shared,
                open: context.url,
                options: [:]
            )
        }
    }
}
