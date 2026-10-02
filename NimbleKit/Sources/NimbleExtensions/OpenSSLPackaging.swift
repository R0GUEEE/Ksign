//
//  OpenSSLPackaging.swift
//  NimbleExtensions
//
//  PKCS#12 and CMS packaging on top of the OpenSSL build the project already
//  links through zsign.
//
//  Why this lives in NimbleExtensions instead of beside the code that uses it:
//  the app target cannot `import OpenSSL`. Vapor pulls in `CNIOBoringSSL`, which
//  declares the same C struct names (crypto_ex_data_st, ASN1_STRING, ...), and
//  the two modules cannot be loaded into one compilation — it fails with
//  "'crypto_ex_data_st::ctx' from module 'OpenSSL.crypto' is not present in
//  definition of 'struct crypto_ex_data_st' in module 'CNIOBoringSSL'".
//  A separate module with no Vapor in it compiles the two in isolation, and the
//  app only ever sees the Swift API below.
//

import Foundation
import OpenSSL

public enum OpenSSLPackagingError: LocalizedError {
	case invalidCertificate
	case invalidPrivateKey
	case pkcs12Failed(String)
	case cmsFailed(String)

	public var errorDescription: String? {
		switch self {
		case .invalidCertificate:
			return "The DER certificate could not be read."
		case .invalidPrivateKey:
			return "The DER private key could not be read."
		case .pkcs12Failed(let reason):
			return "Could not build the PKCS#12 container — \(reason)."
		case .cmsFailed(let reason):
			return "Could not build the CMS container — \(reason)."
		}
	}
}

public enum OpenSSLPackaging {

	/// Builds a password protected PKCS#12 container holding a certificate and
	/// its private key. Both inputs are DER; the key is PKCS#8 (`PrivateKeyInfo`).
	///
	/// A MAC is always written, which is what every other reader (including this
	/// project's own `p12_password_check`) verifies a password against.
	public static func pkcs12(
		certificateDER: [UInt8],
		privateKeyDER: [UInt8],
		password: String,
		name: String
	) throws -> Data {
		let certificate = certificateDER.withUnsafeBufferPointer { buffer in
			var pointer = buffer.baseAddress
			return d2i_X509(nil, &pointer, numericCast(buffer.count))
		}
		guard let certificate else { throw OpenSSLPackagingError.invalidCertificate }
		defer { X509_free(certificate) }

		let pkey = privateKeyDER.withUnsafeBufferPointer { buffer in
			var pointer = buffer.baseAddress
			return d2i_AutoPrivateKey(nil, &pointer, numericCast(buffer.count))
		}
		guard let pkey else { throw OpenSSLPackagingError.invalidPrivateKey }
		defer { EVP_PKEY_free(pkey) }

		let container = password.withCString { passphrase in
			name.withCString { label in
				PKCS12_create(passphrase, label, pkey, certificate, nil, 0, 0, 2048, 2048, 0)
			}
		}
		guard let container else { throw OpenSSLPackagingError.pkcs12Failed("OpenSSL refused to create it") }
		defer { PKCS12_free(container) }

		guard let bio = BIO_new(BIO_s_mem()) else {
			throw OpenSSLPackagingError.pkcs12Failed("no memory BIO")
		}
		defer { BIO_free(bio) }

		guard i2d_PKCS12_bio(bio, container) == 1 else {
			throw OpenSSLPackagingError.pkcs12Failed("OpenSSL refused to encode it")
		}

		var output = Data()
		var chunk = [UInt8](repeating: 0, count: 4096)
		while true {
			let read = BIO_read(bio, &chunk, numericCast(chunk.count))
			if read <= 0 { break }
			output.append(contentsOf: chunk[0 ..< Int(read)])
		}
		return output
	}

	/// Signs `content` into an encapsulated CMS `SignedData` with the given
	/// certificate and key. Same container a real `.mobileprovision` uses; the
	/// payload stays readable inside it, which is all zsign and iOS look for.
	public static func signedCMS(
		content: Data,
		certificateDER: [UInt8],
		privateKeyDER: [UInt8]
	) throws -> Data {
		let certificate = certificateDER.withUnsafeBufferPointer { buffer in
			var pointer = buffer.baseAddress
			return d2i_X509(nil, &pointer, numericCast(buffer.count))
		}
		guard let certificate else { throw OpenSSLPackagingError.invalidCertificate }
		defer { X509_free(certificate) }

		let pkey = privateKeyDER.withUnsafeBufferPointer { buffer in
			var pointer = buffer.baseAddress
			return d2i_AutoPrivateKey(nil, &pointer, numericCast(buffer.count))
		}
		guard let pkey else { throw OpenSSLPackagingError.invalidPrivateKey }
		defer { EVP_PKEY_free(pkey) }

		let cms = try content.withUnsafeBytes { rawBuffer in
			guard let base = rawBuffer.baseAddress else {
				throw OpenSSLPackagingError.cmsFailed("nothing to sign")
			}
			guard let data = BIO_new_mem_buf(base, numericCast(rawBuffer.count)) else {
				throw OpenSSLPackagingError.cmsFailed("no memory BIO")
			}
			defer { BIO_free(data) }

			guard let cms = CMS_sign(certificate, pkey, nil, data, numericCast(CMS_BINARY)) else {
				throw OpenSSLPackagingError.cmsFailed("OpenSSL refused to sign it")
			}
			return cms
		}
		defer { CMS_ContentInfo_free(cms) }

		guard let bio = BIO_new(BIO_s_mem()) else {
			throw OpenSSLPackagingError.cmsFailed("no memory BIO")
		}
		defer { BIO_free(bio) }

		guard i2d_CMS_bio(bio, cms) == 1 else {
			throw OpenSSLPackagingError.cmsFailed("OpenSSL refused to encode it")
		}

		var output = Data()
		var chunk = [UInt8](repeating: 0, count: 4096)
		while true {
			let read = BIO_read(bio, &chunk, numericCast(chunk.count))
			if read <= 0 { break }
			output.append(contentsOf: chunk[0 ..< Int(read)])
		}
		return output
	}

	// The result is drained by hand rather than through a helper: `BIO` is an
	// opaque struct, and nothing here needs to name how Swift imports it.
}
