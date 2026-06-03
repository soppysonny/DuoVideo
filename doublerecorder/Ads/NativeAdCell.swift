import UIKit
import GoogleMobileAds

final class NativeAdCell: UITableViewCell {

    static let reuseID = "NativeAdCell"
    static let height: CGFloat = 120

    private let adView        = NativeAdView()
    private let adBadge       = UILabel()
    private let iconImgView   = UIImageView()
    private let headlineLbl   = UILabel()
    private let advertiserLbl = UILabel()
    private let bodyLbl       = UILabel()
    private let ctaBtn        = UIButton(type: .custom)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle  = .none
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        adView.backgroundColor    = UIColor(white: 0.11, alpha: 1)
        adView.layer.cornerRadius = 10
        adView.clipsToBounds      = true
        adView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(adView)

        // AD badge
        adBadge.text            = "AD"
        adBadge.font            = UIFont.monospacedSystemFont(ofSize: 8, weight: .bold)
        adBadge.textColor       = UIColor(white: 0.55, alpha: 1)
        adBadge.backgroundColor = UIColor(white: 0.22, alpha: 1)
        adBadge.textAlignment   = .center
        adBadge.layer.cornerRadius = 3
        adBadge.clipsToBounds   = true
        adBadge.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(adBadge)

        // Icon
        iconImgView.contentMode        = .scaleAspectFill
        iconImgView.backgroundColor    = UIColor(white: 0.18, alpha: 1)
        iconImgView.layer.cornerRadius = 8
        iconImgView.clipsToBounds      = true
        iconImgView.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(iconImgView)
        adView.iconView = iconImgView

        // Headline
        headlineLbl.font          = UIFont.systemFont(ofSize: 13, weight: .semibold)
        headlineLbl.textColor     = .white
        headlineLbl.numberOfLines = 1
        headlineLbl.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(headlineLbl)
        adView.headlineView = headlineLbl

        // Advertiser
        advertiserLbl.font          = UIFont.systemFont(ofSize: 10)
        advertiserLbl.textColor     = UIColor.white.withAlphaComponent(0.4)
        advertiserLbl.numberOfLines = 1
        advertiserLbl.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(advertiserLbl)
        adView.advertiserView = advertiserLbl

        // Body
        bodyLbl.font          = UIFont.systemFont(ofSize: 11)
        bodyLbl.textColor     = UIColor.white.withAlphaComponent(0.55)
        bodyLbl.numberOfLines = 2
        bodyLbl.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(bodyLbl)
        adView.bodyView = bodyLbl

        // CTA button
        ctaBtn.titleLabel?.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        ctaBtn.setTitleColor(UIColor(white: 0.05, alpha: 1), for: .normal)
        ctaBtn.backgroundColor    = UIColor(red: 1, green: 0.698, blue: 0.247, alpha: 0.9)
        ctaBtn.layer.cornerRadius = 8
        ctaBtn.contentEdgeInsets  = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
        ctaBtn.isUserInteractionEnabled = false
        ctaBtn.translatesAutoresizingMaskIntoConstraints = false
        adView.addSubview(ctaBtn)
        adView.callToActionView = ctaBtn

        NSLayoutConstraint.activate([
            adView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            adView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            adView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            adView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            adBadge.topAnchor.constraint(equalTo: adView.topAnchor, constant: 9),
            adBadge.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
            adBadge.widthAnchor.constraint(equalToConstant: 22),
            adBadge.heightAnchor.constraint(equalToConstant: 14),

            iconImgView.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
            iconImgView.bottomAnchor.constraint(equalTo: adView.bottomAnchor, constant: -12),
            iconImgView.widthAnchor.constraint(equalToConstant: 38),
            iconImgView.heightAnchor.constraint(equalToConstant: 38),

            ctaBtn.trailingAnchor.constraint(equalTo: adView.trailingAnchor, constant: -12),
            ctaBtn.centerYAnchor.constraint(equalTo: adView.centerYAnchor, constant: 8),
            ctaBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),

            headlineLbl.topAnchor.constraint(equalTo: adView.topAnchor, constant: 12),
            headlineLbl.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
            headlineLbl.trailingAnchor.constraint(equalTo: ctaBtn.leadingAnchor, constant: -8),

            advertiserLbl.topAnchor.constraint(equalTo: headlineLbl.bottomAnchor, constant: 4),
            advertiserLbl.leadingAnchor.constraint(equalTo: adView.leadingAnchor, constant: 12),
            advertiserLbl.trailingAnchor.constraint(equalTo: ctaBtn.leadingAnchor, constant: -8),

            bodyLbl.topAnchor.constraint(equalTo: advertiserLbl.bottomAnchor, constant: 4),
            bodyLbl.leadingAnchor.constraint(equalTo: iconImgView.trailingAnchor, constant: 8),
            bodyLbl.trailingAnchor.constraint(equalTo: ctaBtn.leadingAnchor, constant: -8),
            bodyLbl.bottomAnchor.constraint(lessThanOrEqualTo: adView.bottomAnchor, constant: -10),
        ])
    }

    func configure(with nativeAd: NativeAd) {
        (adView.headlineView as? UILabel)?.text    = nativeAd.headline
        (adView.bodyView as? UILabel)?.text        = nativeAd.body
        (adView.advertiserView as? UILabel)?.text  = nativeAd.advertiser
        adView.advertiserView?.isHidden            = nativeAd.advertiser == nil
        (adView.iconView as? UIImageView)?.image   = nativeAd.icon?.image
        adView.iconView?.isHidden                  = nativeAd.icon == nil
        (adView.callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)
        adView.callToActionView?.isHidden          = nativeAd.callToAction == nil
        adView.nativeAd = nativeAd
    }
}
