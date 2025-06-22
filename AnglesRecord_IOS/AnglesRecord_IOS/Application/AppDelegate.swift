//
//  AppDelegate.swift
//  AnglesRecord
//
//  Created by 성현 on 6/20/25.
//

import Firebase
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }
}
