import SwiftUI
import CalendarrCore

/// Every reason there is nothing to show, named. "Never received", "signed out"
/// and "genuinely empty" call for different sentences, and showing the wrong one
/// sends the user looking in the wrong place.
struct WatchStatusView: View {
    let result: SnapshotReadResult
    let language: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var symbol: String {
        switch result {
        case .ok:           return "calendar"
        case .loggedOut:    return "person.crop.circle.badge.xmark"
        case .neverWritten: return "iphone.and.arrow.forward"
        case .incompatible: return "arrow.down.circle"
        case .unreadable:   return "exclamationmark.triangle"
        }
    }

    private var message: String {
        switch result {
        case .ok:           return WatchL10n.t("watch.no_events", language)
        case .loggedOut:    return WatchL10n.t("watch.sign_in", language)
        case .neverWritten: return WatchL10n.t("watch.waiting", language)
        case .incompatible: return WatchL10n.t("watch.update", language)
        case .unreadable:   return WatchL10n.t("watch.unreadable", language)
        }
    }
}
