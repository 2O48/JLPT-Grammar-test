import SwiftUI
import UIKit

enum WenfaFont {
    static func regular(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("YuMincho-Regular", size: size, relativeTo: style)
    }

    static func semibold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("YuMincho-Demibold", size: size, relativeTo: style)
    }

    static func textStyle(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        switch style {
        case .largeTitle: weight == .regular ? regular(34, relativeTo: style) : semibold(34, relativeTo: style)
        case .title: weight == .regular ? regular(28, relativeTo: style) : semibold(28, relativeTo: style)
        case .title2: weight == .regular ? regular(22, relativeTo: style) : semibold(22, relativeTo: style)
        case .title3: weight == .regular ? regular(20, relativeTo: style) : semibold(20, relativeTo: style)
        case .headline: semibold(17, relativeTo: style)
        case .subheadline: weight == .regular ? regular(15, relativeTo: style) : semibold(15, relativeTo: style)
        case .footnote: weight == .regular ? regular(13, relativeTo: style) : semibold(13, relativeTo: style)
        case .caption: weight == .regular ? regular(12, relativeTo: style) : semibold(12, relativeTo: style)
        case .caption2: weight == .regular ? regular(11, relativeTo: style) : semibold(11, relativeTo: style)
        default: weight == .regular ? regular(17, relativeTo: .body) : semibold(17, relativeTo: .body)
        }
    }
}

enum WenfaTypography {
    static func configure() {
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithDefaultBackground()
        navigationAppearance.titleTextAttributes = [.font: UIFont(name: "YuMincho-Demibold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)]
        navigationAppearance.largeTitleTextAttributes = [.font: UIFont(name: "YuMincho-Demibold", size: 34) ?? .systemFont(ofSize: 34, weight: .bold)]
        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance

        let tabItemAppearance = UITabBarItemAppearance()
        tabItemAppearance.normal.titleTextAttributes = [.font: UIFont(name: "YuMincho-Regular", size: 11) ?? .systemFont(ofSize: 11)]
        tabItemAppearance.selected.titleTextAttributes = [.font: UIFont(name: "YuMincho-Demibold", size: 11) ?? .systemFont(ofSize: 11, weight: .semibold)]
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.stackedLayoutAppearance = tabItemAppearance
        tabAppearance.inlineLayoutAppearance = tabItemAppearance
        tabAppearance.compactInlineLayoutAppearance = tabItemAppearance
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
}
