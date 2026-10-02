import Foundation
import CryptoKit

struct EncryptedBackupEnvelope: Codable {
    let version: Int
    let salt: Data
    let nonce: Data
    let ciphertext: Data
    let tag: Data
}

enum EncryptedBackupService {
    enum Error: Swift.Error { case invalidPassword, malformed }

    static func encrypt(_ data: Data, password: String) throws -> Data {
        let salt = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let key = SymmetricKey(data: SHA256.hash(data: Data(password.utf8) + salt))
        let box = try AES.GCM.seal(data, using: key)
        let envelope = EncryptedBackupEnvelope(version: 1, salt: salt, nonce: Data(box.nonce), ciphertext: box.ciphertext, tag: box.tag)
        return try JSONEncoder().encode(envelope)
    }

    static func decrypt(_ data: Data, password: String) throws -> Data {
        let envelope = try JSONDecoder().decode(EncryptedBackupEnvelope.self, from: data)
        guard envelope.version == 1 else { throw Error.malformed }
        let key = SymmetricKey(data: SHA256.hash(data: Data(password.utf8) + envelope.salt))
        do { return try AES.GCM.open(try AES.GCM.SealedBox(nonce: envelope.nonce, ciphertext: envelope.ciphertext, tag: envelope.tag), using: key) }
        catch { throw Error.invalidPassword }
    }
}
