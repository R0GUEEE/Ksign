//
//  AppFeaturesView.swift
//  Ksign
//
//  Created by Nagata Asami on 10/10/25.
//

import SwiftUI
import NimbleViews
import UserNotifications

struct AppFeaturesView: View {
    @StateObject private var _optionsManager = OptionsManager.shared
    
    private var _certificateExpiryNotifications: Binding<Bool> {
        Binding(
            get: { _optionsManager.options.certificateExpiryNotifications ?? false },
            set: { _optionsManager.options.certificateExpiryNotifications = $0 }
        )
    }
    
    private var _certificateExpiryNotifyDaysBefore: Binding<Int> {
        Binding(
            get: { _optionsManager.options.certificateExpiryNotifyDaysBefore ?? 3 },
            set: { _optionsManager.options.certificateExpiryNotifyDaysBefore = $0 }
        )
    }
    
    var body: some View {
        NBList(.localized("App Features")) {
            Section {
                Toggle(isOn: $_optionsManager.options.backgroundAudio) {
                    Label(.localized("Keep app running in background"), systemImage: "arrow.trianglehead.2.clockwise")
                }
            } footer: {
                Text(.localized("This will keep the app running even when you close it, helpful with download or installing ipa."))
            }
            Section {
                Toggle(isOn: $_optionsManager.options.signingLogs) {
                    Label(.localized("Show logs when signing"), systemImage: "terminal")
                }
            } footer: {
                Text(.localized("This will show the logs of the signing process when you start signing."))
            }
            Section {
                Toggle(isOn: $_optionsManager.options.notifications) {
                    Label(.localized("Notify when download is completed"), systemImage: "bell")
                }
                .onChange(of: _optionsManager.options.notifications) { enabled in
                    _requestNotificationAuthorizationIfNeeded(enabled) {
                        _optionsManager.options.notifications = false
                    }
                }
            } footer: {
                Text(.localized("This will notify you when the download is completed."))
            }
            Section {
                Toggle(isOn: _certificateExpiryNotifications) {
                    Label(.localized("Notify before a certificate expires"), systemImage: "calendar.badge.exclamationmark")
                }
                .onChange(of: _certificateExpiryNotifications.wrappedValue) { enabled in
                    _requestNotificationAuthorizationIfNeeded(enabled) {
                        _certificateExpiryNotifications.wrappedValue = false
                    }
                    CertificateExpiryManager.rescheduleAll()
                }
                
                if _certificateExpiryNotifications.wrappedValue {
                    Picker(.localized("Notify Before"), selection: _certificateExpiryNotifyDaysBefore) {
                        ForEach(Options.certificateExpiryNotifyDaysBeforeValues, id: \.self) { days in
                            let label: String = days == 0
                                ? .localized("Day of expiration")
                                : .localized("%lld days before", arguments: days)
                            Text(label)
                                .tag(days)
                        }
                    }
                    .onChange(of: _certificateExpiryNotifyDaysBefore.wrappedValue) { _ in
                        CertificateExpiryManager.rescheduleAll()
                    }
                }
            } footer: {
                Text(.localized("This will notify you ahead of a certificate's expiration date, so you have time to renew it before your signed apps stop opening."))
            }
            Section {
                Toggle(isOn: $_optionsManager.options.saveAppStoreDownloadsToDownloadsFolder) {
                    Label(.localized("Save App Store downloads to Downloads folder"), systemImage: "square.and.arrow.down.fill")
                }
            } footer: {
                Text(.localized("This will save the App Store downloads to the Downloads folder, turning this off will help reduce disk usage."))
            }
        }
        .onChange(of: _optionsManager.options) { _ in
            _optionsManager.saveOptions()
        }
    }

    private func _requestNotificationAuthorizationIfNeeded(_ enabled: Bool, onDenied: @escaping () -> Void) {
        guard enabled else { return }
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async {
                        if !granted {
                            onDenied()
                        }
                    }
                }
            case .denied:
                DispatchQueue.main.async {
                    onDenied()
                    
                    let cancel = UIAlertAction(title: .localized("Cancel"), style: .cancel)
                    let ok = UIAlertAction(title: .localized("Open Settings"), style: .default) { _ in
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    UIAlertController.showAlert(
                        title: .localized("You have denied!"),
                        message: .localized("Please open settings and grant permission to send notifications."),
                        actions: [cancel, ok]
                    )
                }
            case .authorized, .provisional, .ephemeral:
                break
            @unknown default:
                break
            }
        }
    }
}
