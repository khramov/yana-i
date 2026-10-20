import Foundation

/// Values injected from `Config/*.xcconfig` through the Info.plist.
enum AppConfiguration {
    static var cloudKitContainer: String {
        Bundle.main.object(forInfoDictionaryKey: "YanaCloudKitContainer") as? String ?? ""
    }
}
