import GoogleMobileAds
import UIKit

final class NativeAdManager: NSObject {

    private static let adUnitID = "ca-app-pub-1709854646699078/1665536119"

    private var adLoader: AdLoader?
    var onAdLoaded: ((NativeAd) -> Void)?

    func load(rootViewController: UIViewController) {
        let loader = AdLoader(
            adUnitID: Self.adUnitID,
            rootViewController: rootViewController,
            adTypes: [.native],
            options: nil
        )
        loader.delegate = self
        adLoader = loader
        loader.load(Request())
    }
}

extension NativeAdManager: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        onAdLoaded?(nativeAd)
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        // 静默失败，不展示广告
    }
}
