import SwiftUI

@MainActor
enum AppStrings {
    static let map = LocalizedStringKey("tab.map.title")
    static let groups = LocalizedStringKey("tab.groups.title")
    static let notifications = LocalizedStringKey("tab.notifications.title")
    static let profile = LocalizedStringKey("tab.profile.title")

    static let prototypeBadge = LocalizedStringKey("prototype.badge")
    static let backendNotice = LocalizedStringKey("prototype.backendNotice")

    static let mapPreviewTitle = LocalizedStringKey("map.preview.title")
    static let mapPreviewDetail = LocalizedStringKey("map.preview.detail")
    static let arPreviewButton = LocalizedStringKey("map.arPreview.button")
    static let mapPlaceholderTitle = LocalizedStringKey("map.placeholder.title")
    static let mapPlaceholderDetail = LocalizedStringKey("map.placeholder.detail")

    static let groupsPreviewTitle = LocalizedStringKey("groups.preview.title")
    static let groupsPreviewDetail = LocalizedStringKey("groups.preview.detail")

    static let notificationsPreviewTitle = LocalizedStringKey("notifications.preview.title")
    static let notificationsPreviewDetail = LocalizedStringKey("notifications.preview.detail")

    static let profilePreviewTitle = LocalizedStringKey("profile.preview.title")
    static let profilePreviewDetail = LocalizedStringKey("profile.preview.detail")
}
