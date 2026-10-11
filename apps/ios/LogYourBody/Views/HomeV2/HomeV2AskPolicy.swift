//
// HomeV2AskPolicy.swift
// LogYourBody
//
import Foundation

enum HomeV2AskCopy {
    static let title = "Ask"
    static let deleteChat = "Delete chat"
    static let composerPlaceholder = "Ask about your progress"
    static let proofMarker = "Proof"
}

/// A reply is prose plus, when the assistant gives one, a proof line that
/// says what is measured and what is estimated (Pencil C4/C5). The proof
/// renders quieter, never hidden.
struct HomeV2AskReply: Equatable {
    let body: String
    let proof: String?

    static func split(_ text: String) -> HomeV2AskReply {
        let paragraphs = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let index = paragraphs.firstIndex(where: isProof) else {
            return HomeV2AskReply(body: text.trimmingCharacters(in: .whitespacesAndNewlines), proof: nil)
        }
        let proof = paragraphs[index...]
            .map { paragraph -> String in
                if paragraph.lowercased() == HomeV2AskCopy.proofMarker.lowercased() { return "" }
                let stripped = paragraph
                    .replacingOccurrences(of: "\(HomeV2AskCopy.proofMarker):", with: "", options: [.caseInsensitive, .anchored])
                return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let body = paragraphs[..<index].joined(separator: "\n\n")
        return HomeV2AskReply(body: body, proof: proof.isEmpty ? nil : proof)
    }

    private static func isProof(_ paragraph: String) -> Bool {
        let lowered = paragraph.lowercased()
        return lowered == HomeV2AskCopy.proofMarker.lowercased() || lowered.hasPrefix("\(HomeV2AskCopy.proofMarker.lowercased()):")
    }
}
