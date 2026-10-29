import Foundation
import ProtlyCore
import UIKit

// Suggestions and learning on the phone. The rules live in ProtlyCore (Suggester, LearnedWords); this file
// connects the system lexicon, the learned-word store and the memory readout.

extension KeyboardViewController {
    private static let learnedKey = "protly.learnedWords"
    /// Build with true to read the keyboard's memory (now / peak MB) in the bar's right slot when it has no
    /// suggestion. Only for the Sprint 6 phone check; ships false.
    static let showsMemory = false

    /// From viewDidLoad: learned words from the keyboard's own container, and the phone's text replacements and
    /// contact names (no Full Access needed).
    func setUpWords() {
        if let data = UserDefaults.standard.data(forKey: Self.learnedKey),
           let learned = try? JSONDecoder().decode(LearnedWords.self, from: data) {
            session.suggester.learned = learned
        }
        savedChanges = session.suggester.learned.changes
        requestSupplementaryLexicon { [weak self] lexicon in
            // Called on an XPC queue: store the map on the main actor, where the session lives. A contact name
            // comes as its own shortcut ("will" -> "Will"); Suggester treats such an entry as a known word.
            Task { @MainActor in
                guard let self else { return }
                self.session.suggester.lexicon = Dictionary(
                    lexicon.entries.map { ($0.userInput.lowercased(), $0.documentText) },
                    uniquingKeysWith: { first, _ in first }
                )
                self.refreshMode()  // the bar shows what a pick would accept
            }
        }
    }

    /// After every event: the bar's suggestion, and the learned words saved when they changed.
    func refreshWords() {
        var s = session.suggestion
        if s == nil, Self.showsMemory { s = Self.memoryText() }
        if mode.suggestion != s { mode.suggestion = s }
        let learned = session.suggester.learned
        if learned.changes != savedChanges, let data = try? JSONEncoder().encode(learned) {
            UserDefaults.standard.set(data, forKey: Self.learnedKey)
            savedChanges = learned.changes
        }
    }

    /// phys_footprint is what iOS counts against an extension's memory limit.
    static func memoryText() -> String {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "memory ?" }
        let now = Double(info.phys_footprint) / 1_048_576
        let peak = Double(info.ledger_phys_footprint_peak) / 1_048_576
        return String(format: "%.1f / %.1f MB", now, peak)
    }
}
