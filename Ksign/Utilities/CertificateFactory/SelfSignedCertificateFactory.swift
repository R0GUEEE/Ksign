//
//  SelfSignedCertificateFactory.swift
//  Ksign
//
//  Generates a signing identity from nothing: a private key, a matching
//  self-signed X.509 certificate, and a provisioning profile to go with it —
//  the same shape as an imported `.p12` + `.mobileprovision` pair, so the
//  result can be registered through the normal import path and then chosen
//  like any other certificate.
//
//  What this is for: signing without a paid Apple developer certificate. A
//  self-signed identity chains to no Apple root, so it only works where the
//  install path does not validate the chain — a jailbroken device with
//  AppSync, TrollStore, or a device you control. It cannot be used to install
//  through Apple's normal installer, and no Apple service will accept it.
//
//  The key and certificate are produced with library code the project already
//  links (`_CryptoExtras`/Security for the key, swift-certificates for the
//  X.509) and packaged with the OpenSSL that zsign is already built against
//  (`PKCS12_create` for the p12, `CMS_sign` for the profile), so nothing here
//  is a hand-rolled ASN.1 encoder.
//

import Foundation
import Crypto
import X509
import SwiftASN1
import Security
import NimbleExtensions

// MARK: - Request

enum SelfSignedKeyAlgorithm: String, CaseIterable, Identifiable {
	case rsa2048 = "RSA 2048"
	case ecP256 = "EC P-256"

	var id: String { rawValue }

	/// The signature algorithm the certificate is signed with.
	var signatureAlgorithm: X509.Certificate.SignatureAlgorithm {
		self == .rsa2048 ? .sha256WithRSAEncryption : .ecdsaWithSHA256
	}

	/// EC keys cannot do key encipherment, so only RSA asks for it.
	var supportsKeyEncipherment: Bool {
		self == .rsa2048
	}
}

struct SelfSignedCertificateRequest {
	var commonName: String = "Ksign Self-Signed"
	var organization: String = "Ksign"
	var validityDays: Int = 365
	var keyAlgorithm: SelfSignedKeyAlgorithm = .rsa2048
	/// Password the generated `.p12` is protected with. Blank is allowed.
	var password: String = ""
}

struct SelfSignedCertificateProduct {
	var p12: Data
	var provision: Data
	var expirationDate: Date
	var teamIdentifier: String
}

enum SelfSignedCertificateError: LocalizedError {
	case keyGenerationFailed(String)
	case keyExportFailed
	case certificateFailed
	case pkcs12Failed(String)
	case provisionFailed(String)

	var errorDescription: String? {
		switch self {
		case .keyGenerationFailed(let reason):
			return String.localized("Could not generate the private key: %@", arguments: reason)
		case .keyExportFailed:
			return String.localized("Could not export the generated private key.")
		case .certificateFailed:
			return String.localized("Could not build the certificate.")
		case .pkcs12Failed(let reason):
			return String.localized("Could not package the certificate: %@", arguments: reason)
		case .provisionFailed(let reason):
			return String.localized("Could not package the provisioning profile: %@", arguments: reason)
		}
	}
}

// MARK: - Factory

enum SelfSignedCertificateFactory {

	/// Builds a self-signed code signing identity.
	///
	/// Runs off the main thread by design — RSA key generation is slow enough
	/// to be visible on a phone.
	static func generate(_ request: SelfSignedCertificateRequest) throws -> SelfSignedCertificateProduct {
		let now = Date()
		let validityDays = min(max(request.validityDays, 1), 3650)
		let expiration = now.addingTimeInterval(TimeInterval(validityDays) * 24 * 60 * 60)
		let commonName = _nonEmpty(request.commonName, fallback: "Ksign Self-Signed")
		let organization = _nonEmpty(request.organization, fallback: "Ksign")
		let teamIdentifier = _teamIdentifier()

		// MARK: Private key
		let key = try _generateKey(request.keyAlgorithm)

		// MARK: Certificate
		let subject = try DistinguishedName {
			CommonName(commonName)
			OrganizationName(organization)
		}

		let extensions = try X509.Certificate.Extensions {
			Critical(
				BasicConstraints.notCertificateAuthority
			)
			Critical(
				KeyUsage(
					digitalSignature: true,
					keyEncipherment: request.keyAlgorithm.supportsKeyEncipherment
				)
			)
			try ExtendedKeyUsage([.codeSigning])
			SubjectKeyIdentifier(hash: key.certificateKey.publicKey)
		}

		let certificate = try X509.Certificate(
			version: .v3,
			serialNumber: X509.Certificate.SerialNumber(),
			publicKey: key.certificateKey.publicKey,
			notValidBefore: now.addingTimeInterval(-60),
			notValidAfter: expiration,
			issuer: subject,
			subject: subject,
			signatureAlgorithm: request.keyAlgorithm.signatureAlgorithm,
			extensions: extensions,
			issuerPrivateKey: key.certificateKey
		)

		var serializer = DER.Serializer()
		try serializer.serialize(certificate)
		let certificateDER = serializer.serializedBytes

		// MARK: Provisioning profile payload
		let profile = _profilePlist(
			commonName: commonName,
			organization: organization,
			teamIdentifier: teamIdentifier,
			certificateDER: Data(certificateDER),
			creationDate: now,
			expirationDate: expiration,
			validityDays: validityDays
		)

		// MARK: Packaging (OpenSSL)
		let packaged = try _package(
			certificateDER: certificateDER,
			privateKeyDER: key.pkcs8,
			password: request.password,
			name: commonName,
			profile: profile
		)

		return SelfSignedCertificateProduct(
			p12: packaged.p12,
			provision: packaged.provision,
			expirationDate: expiration,
			teamIdentifier: teamIdentifier
		)
	}

	// MARK: - Key generation

	private struct GeneratedKey {
		var certificateKey: X509.Certificate.PrivateKey
		/// PKCS#8 `PrivateKeyInfo`, what OpenSSL and every other tool expects.
		var pkcs8: [UInt8]
	}

	private static func _generateKey(_ algorithm: SelfSignedKeyAlgorithm) throws -> GeneratedKey {
		switch algorithm {
		case .ecP256:
			let key = P256.Signing.PrivateKey()
			return GeneratedKey(
				certificateKey: X509.Certificate.PrivateKey(key),
				pkcs8: Array(key.derRepresentation)
			)

		case .rsa2048:
			var error: Unmanaged<CFError>?
			let attributes: [String: Any] = [
				kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
				kSecAttrKeySizeInBits as String: 2048,
				kSecAttrIsPermanent as String: false,
			]
			guard let secKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
				throw SelfSignedCertificateError.keyGenerationFailed("Security framework returned no key")
			}

			let certificateKey: X509.Certificate.PrivateKey
			do {
				certificateKey = try X509.Certificate.PrivateKey(secKey)
			} catch {
				throw SelfSignedCertificateError.keyGenerationFailed(error.localizedDescription)
			}

			// RSA external representations come back as PKCS#1, which OpenSSL
			// reads through the PKCS#8 wrapper below.
			guard let pkcs1 = SecKeyCopyExternalRepresentation(secKey, &error) as Data? else {
				throw SelfSignedCertificateError.keyExportFailed
			}

			return GeneratedKey(
				certificateKey: certificateKey,
				pkcs8: _pkcs8(fromPKCS1: [UInt8](pkcs1))
			)
		}
	}

	/// Wraps a PKCS#1 `RSAPrivateKey` in the PKCS#8 `PrivateKeyInfo` that
	/// surrounds it — three fixed fields and a length, not a general encoder.
	private static func _pkcs8(fromPKCS1 pkcs1: [UInt8]) -> [UInt8] {
		var body: [UInt8] = [
			0x02, 0x01, 0x00,             // version 0
			0x30, 0x0d,                   // AlgorithmIdentifier
			0x06, 0x09,                   // OID rsaEncryption, 9 bytes
			0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
			0x05, 0x00,                   // NULL parameters
		]
		body += _derElement(0x04, pkcs1)  // privateKey OCTET STRING
		return _derElement(0x30, body)
	}

	private static func _derElement(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
		[tag] + _derLength(content.count) + content
	}

	private static func _derLength(_ count: Int) -> [UInt8] {
		if count < 0x80 { return [UInt8(count)] }

		var remaining = count
		var bytes: [UInt8] = []
		while remaining > 0 {
			bytes.insert(UInt8(remaining & 0xff), at: 0)
			remaining >>= 8
		}
		return [0x80 | UInt8(bytes.count)] + bytes
	}

	// MARK: - Provisioning profile

	/// A profile with the shape iOS and zsign expect. zsign reads it with
	/// `GetCMSContent` -> `TeamIdentifier` and, failing a certificate in the
	/// p12, matches the private key against `DeveloperCertificates`, so the
	/// generated certificate has to be listed there.
	private static func _profilePlist(
		commonName: String,
		organization: String,
		teamIdentifier: String,
		certificateDER: Data,
		creationDate: Date,
		expirationDate: Date,
		validityDays: Int
	) -> [String: Any] {
		[
			"AppIDName": commonName,
			"ApplicationIdentifierPrefix": [teamIdentifier],
			"CreationDate": creationDate,
			"ExpirationDate": expirationDate,
			// Ksign's own certificate reader requires this key to be present;
			// it is the profile's binary form, which has no meaning for a
			// profile that was not issued by Apple, so the certificate goes in.
			"DER-Encoded-Profile": certificateDER,
			"DeveloperCertificates": [certificateDER],
			"Entitlements": [
				"application-identifier": "\(teamIdentifier).*",
				"com.apple.developer.team-identifier": teamIdentifier,
				"get-task-allow": true,
				"keychain-access-groups": ["\(teamIdentifier).*"],
			],
			"IsXcodeManaged": false,
			"Name": commonName,
			"Platform": ["iOS"],
			"ProvisionsAllDevices": true,
			"TeamIdentifier": [teamIdentifier],
			"TeamName": organization,
			"TimeToLive": validityDays,
			"UUID": UUID().uuidString.uppercased(),
			"Version": 1,
		]
	}

	// MARK: - Packaging

	/// Packaging runs in NimbleExtensions, which is the one module that can talk
	/// to OpenSSL — see the note at the top of `OpenSSLPackaging`.
	private static func _package(
		certificateDER: [UInt8],
		privateKeyDER: [UInt8],
		password: String,
		name: String,
		profile: [String: Any]
	) throws -> (p12: Data, provision: Data) {
		guard let plist = try? PropertyListSerialization.data(
			fromPropertyList: profile,
			format: .xml,
			options: 0
		) else {
			throw SelfSignedCertificateError.provisionFailed("the profile could not be serialised")
		}

		do {
			let p12 = try OpenSSLPackaging.pkcs12(
				certificateDER: certificateDER,
				privateKeyDER: privateKeyDER,
				password: password,
				name: name
			)
			let provision = try OpenSSLPackaging.signedCMS(
				content: plist,
				certificateDER: certificateDER,
				privateKeyDER: privateKeyDER
			)
			return (p12: p12, provision: provision)
		} catch let error as OpenSSLPackagingError {
			switch error {
			case .pkcs12Failed(let reason):
				throw SelfSignedCertificateError.pkcs12Failed(reason)
			case .cmsFailed(let reason):
				throw SelfSignedCertificateError.provisionFailed(reason)
			case .invalidCertificate, .invalidPrivateKey:
				throw SelfSignedCertificateError.keyExportFailed
			}
		}
	}

	// MARK: - Helpers

	private static func _nonEmpty(_ value: String, fallback: String) -> String {
		let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
		return trimmed.isEmpty ? fallback : trimmed
	}

	/// A ten character team identifier, the shape Apple uses (`A1B2C3D4E5`).
	/// It only has to be consistent between the certificate and the profile —
	/// it genuinely identifies nothing.
	private static func _teamIdentifier() -> String {
		let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
		return String((0 ..< 10).map { _ in alphabet.randomElement() ?? "A" })
	}
}
