import Foundation
import CryptoKit

// CI uses ephemeral keys in a private temporary directory. Never prints a private key.
let args = CommandLine.arguments
if args.count == 4 && args[1] == "generate" {
    let key = Curve25519.Signing.PrivateKey()
    let secret = URL(fileURLWithPath: args[2])
    guard !FileManager.default.fileExists(atPath: secret.path) else { fatalError("Refusing to replace existing update key") }
    try key.rawRepresentation.base64EncodedData().write(to: secret, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secret.path)
    try key.publicKey.rawRepresentation.base64EncodedData().write(to: URL(fileURLWithPath: args[3]))
} else if args.count == 5 && args[1] == "verify" {
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: Data(base64Encoded: args[3])!)
    let valid = key.isValidSignature(Data(base64Encoded: args[4])!, for: try Data(contentsOf: URL(fileURLWithPath: args[2])))
    if !valid { fputs("Update signature rejected\n", stderr); exit(1) }
} else {
    fputs("Usage: update-key generate PRIVATE_FILE PUBLIC_FILE | verify ARCHIVE PUBLIC_KEY SIGNATURE\n", stderr)
    exit(2)
}
