//
//  CertificateExpiryManager.swift
//  Ksign
//
//  Schedules a local notification ahead of a certificate's expiration date,
//  so users get a heads-up before their signed apps stop opening — requested
//  in https://github.com/Nyasami/Ksign/issues/21 ("Certificate expiration
//  notifications: Send a notification [...] before a certificate is
//  revoked, giving users time to renew or take action").
//

import Foundation
import UserNotifications
import CoreData

enum CertificateExpiryManager {
	private static let identifierPrefix = "ksign.certificateExpiry."
	
	/// Schedules (or re-schedules) the expiry notification for a single
	/// certificate, based on the user's configured lead time. No-ops if the
	/// feature is disabled, the certificate is already revoked, or the
	/// resulting fire date has already passed.
	static func schedule(for cert: CertificatePair) {
		let identifier = identifierPrefix + (cert.uuid ?? UUID().uuidString)
		
		UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
		
		guard
			OptionsManager.shared.options.certificateExpiryNotifications ?? false,
			!cert.revoked,
			let expiration = cert.expiration
		else {
			return
		}
		
		let daysBefore = OptionsManager.shared.options.certificateExpiryNotifyDaysBefore ?? 3
		guard let fireDate = Calendar.current.date(byAdding: .day, value: -daysBefore, to: expiration) else {
			return
		}
		
		// Don't bother scheduling something in the past — covers both an
		// already-expired certificate and a lead time longer than what's left.
		guard fireDate > Date() else { return }
		
		var components = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
		components.hour = 9
		components.minute = 0
		
		let content = UNMutableNotificationContent()
		content.title = .localized("Certificate Expiring Soon")
		let name = cert.nickname ?? .localized("Your certificate")
		content.body = daysBefore == 0
			? .localized("%@ expires today.", arguments: name)
			: .localized("%@ expires in %lld days.", arguments: name, daysBefore)
		content.sound = .default
		
		let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
		let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
		
		UNUserNotificationCenter.current().add(request) { error in
			if let error {
				print("Failed to schedule certificate expiry notification: \(error.localizedDescription)")
			}
		}
	}
	
	/// Cancels any pending expiry notification for a certificate — call this
	/// when it's deleted or found to be revoked.
	static func cancel(for cert: CertificatePair) {
		let identifier = identifierPrefix + (cert.uuid ?? "")
		UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
	}
	
	/// Cancels every pending expiry notification. Needed when certificates are
	/// removed through a batch delete (`NSBatchDeleteRequest`), which bypasses
	/// Core Data change tracking so `cancel(for:)` never runs per object — the
	/// Reset screen deletes these exactly that way.
	static func cancelAll(completion: (() -> Void)? = nil) {
		UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
			let identifiers = requests
				.map(\.identifier)
				.filter { $0.hasPrefix(identifierPrefix) }
			
			UNUserNotificationCenter.current()
				.removePendingNotificationRequests(withIdentifiers: identifiers)
			completion?()
		}
	}
	
	/// Re-evaluates every stored certificate against the current settings.
	/// Call this on launch (certificates may have been added before this
	/// feature existed, or the lead time/toggle may have just changed).
	static func rescheduleAll(context: NSManagedObjectContext = Storage.shared.context) {
		let request = CertificatePair.fetchRequest()
		
		guard let certificates = try? context.fetch(request) else { return }
		
		for cert in certificates {
			schedule(for: cert)
		}
	}
}
