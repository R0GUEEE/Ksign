//
//  LocalCertificateAuthority.swift
//  Ksign
//
//  Generates a self-contained local Certificate Authority and a leaf TLS
//  certificate for the on-device installer server.
//
//  This replaces the dependency on https://backloop.dev, a free service that
//  used to hand out a publicly-trusted wildcard certificate (plus its private
//  key!) for "*.backloop.dev" so installer traffic to 127.0.0.1 could use a
//  browser-trusted HTTPS connection without anything installed into the
//  device's trust store. The service was discontinued on 2026-09-04 because
//  every certificate it published was, by definition, compromised the moment
//  its private key went public — Certificate Transparency monitoring got
//  faster than the reissue cycle could keep up with.
//
//  The replacement follows the exact approach backloop.dev's own farewell
//  page recommends (the "mkcert" approach): generate your own root CA,
//  install just that root into the device's trust store once, and sign
//  leaf certificates from it locally. Nothing here is ever uploaded
//  anywhere, so there is nothing for a CT log scanner to find and nothing
//  that can be revoked out from under the app.
//

import Foundation
import Crypto
import X509
import SwiftASN1
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum LocalCertificateAuthority {

	/// Result of generating (or loading) the local CA + leaf server certificate.
	struct Pack {
		/// PEM-encoded leaf certificate (what the server presents to clients).
		var cert: String
		/// PEM-encoded leaf certificate's private key.
		var key: String
		/// PEM-encoded root CA certificate (what the user installs/trusts once).
		var ca: String
		/// DER-encoded root CA certificate. iOS's "Install Profile" trust flow
		/// only reliably triggers for a `.cer`/`.der` file, not a PEM text file.
		var caDER: Data
		/// Hostname the leaf certificate is valid for (the server's SNI/common name).
		var commonName: String
	}

	// MARK: - Public API

	/// Hostname used for the server's TLS identity. Unlike `*.backloop.dev`,
	/// which relied on real public DNS resolving to 127.0.0.1, this local CA
	/// has no DNS to lean on — so the server is identified by the loopback
	/// IP literal directly. The leaf certificate carries this as an IP
	/// Subject Alternative Name (not just a DNS name), which is what lets a
	/// client validate `https://127.0.0.1:<port>/...` without any DNS at all.
	static let commonName = "127.0.0.1"

	/// Generates a brand-new root CA and a leaf certificate signed by it,
	/// valid for `localhost` and the loopback addresses `127.0.0.1` / `::1`.
	///
	/// - Parameter validityDays: How long the leaf certificate should remain
	///   valid for. Kept short-ish by default since it is trivial to
	///   regenerate locally (no network round trip, no revocation risk).
	static func generate(validityDays: Int = 825) throws -> Pack {
		let now = Date()
		let notAfter = now.addingTimeInterval(TimeInterval(validityDays) * 24 * 60 * 60)

		// MARK: Root CA
		let caPrivateKey = P256.Signing.PrivateKey()
		let caKey = X509.Certificate.PrivateKey(caPrivateKey)

		let caSubject = try DistinguishedName {
			CommonName("Ksign Local CA")
			OrganizationName("Ksign")
		}

		let caExtensions = try X509.Certificate.Extensions {
			Critical(
				BasicConstraints.isCertificateAuthority(maxPathLength: 0)
			)
			Critical(
				KeyUsage(keyCertSign: true, cRLSign: true)
			)
			SubjectKeyIdentifier(hash: caKey.publicKey)
		}

		let caCertificate = try X509.Certificate(
			version: .v3,
			serialNumber: X509.Certificate.SerialNumber(),
			publicKey: caKey.publicKey,
			notValidBefore: now,
			notValidAfter: notAfter,
			issuer: caSubject,
			subject: caSubject,
			signatureAlgorithm: .ecdsaWithSHA256,
			extensions: caExtensions,
			issuerPrivateKey: caKey
		)

		// MARK: Leaf (server) certificate, signed by the CA above
		let leafPrivateKey = P256.Signing.PrivateKey()
		let leafKey = X509.Certificate.PrivateKey(leafPrivateKey)

		let leafSubject = try DistinguishedName {
			CommonName(commonName)
			OrganizationName("Ksign")
		}

		let leafExtensions = try X509.Certificate.Extensions {
			Critical(
				BasicConstraints.notCertificateAuthority
			)
			Critical(
				KeyUsage(digitalSignature: true, keyEncipherment: true)
			)
			try ExtendedKeyUsage([.serverAuth])
			SubjectAlternativeNames([
				.dnsName("localhost"),
				.ipAddress(ASN1OctetString(contentBytes: ArraySlice(ipv4Octets("127.0.0.1")))),
				.ipAddress(ASN1OctetString(contentBytes: ArraySlice(ipv6Octets("::1")))),
			])
			SubjectKeyIdentifier(hash: leafKey.publicKey)
			AuthorityKeyIdentifier(keyIdentifier: SubjectKeyIdentifier(hash: caKey.publicKey).keyIdentifier)
		}

		let leafCertificate = try X509.Certificate(
			version: .v3,
			serialNumber: X509.Certificate.SerialNumber(),
			publicKey: leafKey.publicKey,
			notValidBefore: now,
			notValidAfter: notAfter,
			issuer: caSubject,
			subject: leafSubject,
			signatureAlgorithm: .ecdsaWithSHA256,
			extensions: leafExtensions,
			issuerPrivateKey: caKey
		)

		let caPEM = try caCertificate.serializeAsPEM().pemString
		var caDERSerializer = DER.Serializer()
		try caDERSerializer.serialize(caCertificate)
		let caDER = Data(caDERSerializer.serializedBytes)
		
		let leafCertPEM = try leafCertificate.serializeAsPEM().pemString
		let leafKeyPEM = try leafKey.serializeAsPEM().pemString

		return Pack(
			cert: leafCertPEM,
			key: leafKeyPEM,
			ca: caPEM,
			caDER: caDER,
			commonName: commonName
		)
	}

	// MARK: - IP address byte helpers

	/// Converts a dotted-decimal IPv4 address string into its 4-byte
	/// network-order representation, as required by RFC 5280 §4.2.1.6 for
	/// the `iPAddress` choice of `GeneralName`.
	private static func ipv4Octets(_ address: String) -> [UInt8] {
		var addr = in_addr()
		guard inet_pton(AF_INET, address, &addr) == 1 else { return [127, 0, 0, 1] }
		return withUnsafeBytes(of: &addr) { Array($0) }
	}

	/// Converts an IPv6 address string into its 16-byte network-order
	/// representation.
	private static func ipv6Octets(_ address: String) -> [UInt8] {
		var addr = in6_addr()
		guard inet_pton(AF_INET6, address, &addr) == 1 else {
			return [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
		}
		return withUnsafeBytes(of: &addr) { Array($0) }
	}
}
