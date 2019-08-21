import Intents
import IntentsUI

@objc(SiriShortcuts) class SiriShortcuts : CDVPlugin {
    var activity: NSUserActivity?
    var shortcutPresentedDelegate: ShortcutPresentedDelegate?

    public static func getActivityName() -> String? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }

        // corresponds to the NSUserActivityTypes
        let activityName = identifier + ".shortcut"

        return activityName
    }

    @objc(add:) func add(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            if #available(iOS 12.0, *) {
                self.activity = self.createUserActivity(from: command, makeActive: false)

                if self.activity != nil {
                    self.shortcutPresentedDelegate = ShortcutPresentedDelegate(command: command, shortcuts: self)

                    let shortcut = INShortcut(userActivity: self.activity!)
                    let viewController = INUIAddVoiceShortcutViewController(shortcut: shortcut)
                    viewController.delegate = self.shortcutPresentedDelegate!


                    DispatchQueue.main.async {
                        self.viewController?.present(viewController, animated: true, completion: nil)
                    }
                } else {
                    // shortcut not presented
                    self.sendStatusError(command)
                }
            }
        })
    }

    @objc(edit:) func edit(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            if #available(iOS 12.0, *) {
                guard let uuidString = command.arguments[0] as? String else {
                    return self.sendStatusError(command)
                }

                guard let uuid = UUID.init(uuidString: uuidString) else {
                    return self.sendStatusError(command)
                }

                INVoiceShortcutCenter.shared.getVoiceShortcut(with: uuid) { (voiceShortcut, error) in
                    guard let voiceShortcut = voiceShortcut else {
                        if let error = error as NSError? {
                            NSLog("Failed to fetch voice shortcuts with error: %@", error)
                        }
                        self.sendStatusError(command)
                        return
                    }
                    let viewController = INUIEditVoiceShortcutViewController(voiceShortcut: voiceShortcut)
                    viewController.delegate = self.shortcutPresentedDelegate!

                    DispatchQueue.main.async {
                        self.viewController?.present(viewController, animated: true, completion: nil)
                    }
                }
            } else {
                // shortcuts not presented
                self.sendStatusError(command)
            }
        })
    }

    @objc(getAll:) func getAll(_ command: CDVInvokedUrlCommand) {
        self.commandDelegate!.run(inBackground: {
            if #available(iOS 12.0, *) {
                INVoiceShortcutCenter.shared.getAllVoiceShortcuts { (voiceShortcuts, error) in
                    guard let voiceShortcuts = voiceShortcuts else {
                        if let error = error as NSError? {
                            NSLog("Failed to fetch voice shortcuts with error: %@", error)
                            self.sendStatusError(command)
                        }
                        return
                    }

                    var returnData = [[String:Any]]()

                    for sc in voiceShortcuts {

                        let title = sc.shortcut.userActivity?.title
                        var userInfo =  sc.shortcut.userActivity?.userInfo ?? [:]
                        let uuid = sc.identifier
                        let persistentIdentifier = userInfo["persistentIdentifier"]
                        let invocationPhrase = sc.invocationPhrase

                        userInfo.removeValue(forKey: "persistentIdentifier")

                        returnData.append([
                            "title": title as Any,
                            "persistentIdentifier": persistentIdentifier!,
                            "uuid": uuid,
                            "userInfo": userInfo,
                            "invocationPhrase": invocationPhrase
                            ])
                    }

                    let pluginResult = CDVPluginResult(
                        status: CDVCommandStatus_OK,
                        messageAs: returnData
                    )

                    self.send(pluginResult: pluginResult!, command: command)
                }
            } else {
                // shortcuts not presented
                self.sendStatusError(command)
            }
        })
    }

    @objc(getActivated:) func getActivated(_ command: CDVInvokedUrlCommand) {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate

        self.commandDelegate!.run(inBackground: {
            if #available(iOS 12.0, *) {
                var pluginResult = CDVPluginResult(
                    status: CDVCommandStatus_OK
                )

                if let userActivity = appDelegate.userActivity {
                    let title = userActivity.title
                    var userInfo = userActivity.userInfo ?? [:]
                    let persistentIdentifier = userInfo["persistentIdentifier"]

                    userInfo.removeValue(forKey: "persistentIdentifier")

                    let returnData = [
                        "title": title,
                        "persistentIdentifier": persistentIdentifier,
                        "userInfo": userInfo,
                    ]

                    pluginResult = CDVPluginResult(
                        status: CDVCommandStatus_OK,
                        messageAs: returnData as [AnyHashable: Any]
                    )

                    let clear = command.arguments[0] as? Bool ?? true
                    if clear {
                        appDelegate.userActivity = nil
                    }
                }

                self.send(pluginResult: pluginResult!, command: command)
            } else {
                self.sendStatusError(command)
            }
        })
    }

    func createUserActivity(from command: CDVInvokedUrlCommand, makeActive: Bool) -> NSUserActivity? {
        if #available(iOS 12.0, *) {
            // corresponds to the NSUserActivityTypes
            guard let activityName = SiriShortcuts.getActivityName() else { return nil }

            // extract all features
            guard let persistentIdentifier = command.arguments[0] as? String else { return nil }
            guard let title = command.arguments[1] as? String else { return nil }
            let suggestedInvocationPhrase = command.arguments[2] as? String
            var userInfo = command.arguments[3] as? [String: Any] ?? [:]

            var isEligibleForSearch = true
            var isEligibleForPrediction = true

            if command.arguments.count > 5 {
                isEligibleForSearch = command.arguments[4] as? Bool ?? true
                isEligibleForPrediction = command.arguments[5] as? Bool ?? true
            }

            userInfo["persistentIdentifier"] = persistentIdentifier

            // create shortcut
            let activity = NSUserActivity(activityType: activityName)
            activity.title = title
            activity.suggestedInvocationPhrase = suggestedInvocationPhrase
            activity.persistentIdentifier = NSUserActivityPersistentIdentifier(persistentIdentifier)
            activity.isEligibleForSearch = isEligibleForSearch
            activity.isEligibleForPrediction = isEligibleForPrediction

            if (makeActive) {
                ActivityDataHolder.setUserInfo(userInfo)

                activity.needsSave = true

                // donate shortcut
                self.viewController?.userActivity = activity
            } else {
                activity.userInfo = userInfo
            }

            return activity
        } else {
            return nil
        }
    }

    func sendStatusOk(_ command: CDVInvokedUrlCommand) {
        self.send(status: CDVCommandStatus_OK, command: command)
    }

    func sendStatusError(_ command: CDVInvokedUrlCommand, error: String? = nil) {
        var message = error

        if message == nil {
            message = "Error while performing shortcut operation, user might not run iOS 12."
        }

        let pluginResult = CDVPluginResult(
            status: CDVCommandStatus_ERROR,
            messageAs: message
        )

        self.send(pluginResult: pluginResult!, command: command)
    }

    func send(status: CDVCommandStatus, command: CDVInvokedUrlCommand) {
        let pluginResult = CDVPluginResult(
            status: status
        )

        self.send(pluginResult: pluginResult!, command: command)
    }

    func send(pluginResult: CDVPluginResult, command: CDVInvokedUrlCommand) {
        self.commandDelegate!.send(
            pluginResult,
            callbackId: command.callbackId
        )
    }
}
