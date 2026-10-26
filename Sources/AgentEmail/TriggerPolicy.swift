import Foundation

struct TriggerPolicy {
    let ownAddress: String
    let prefix: String

    func accepts(sender: String, recipients: [String], subject: String, autoSubmitted: String? = nil) -> Bool {
        let address = ownAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !address.isEmpty, !prefix.isEmpty,
              sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == address,
              recipients.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == address }),
              autoSubmitted == nil || autoSubmitted?.lowercased() == "no" else { return false }
        return subject.hasPrefix(prefix) && !subject.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
