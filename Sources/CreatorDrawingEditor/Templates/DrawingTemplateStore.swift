import CreatorDrawing
import Foundation
import Observation

/// The person's drawing templates (DR-5 R10): sorted by name, each change saved to the folder before the store changes (a store with
/// no folder is memory only, every test's). A failed save or delete leaves the store as it was and says why in `saveProblem`.
@MainActor @Observable
public final class DrawingTemplateStore {
    public private(set) var templates: [DrawingTemplate] = []
    /// One sentence per file that was skipped when the folder was read.
    public private(set) var loadProblems: [String] = []
    /// The last failed change's sentence; cleared by the next change that succeeds.
    public private(set) var saveProblem: String?
    private let folder: DrawingTemplateFolder?

    public init(folder: DrawingTemplateFolder? = nil) {
        self.folder = folder
        if let folder {
            let loaded = folder.load()
            templates = Self.sorted(loaded.templates)
            loadProblems = loaded.problems
        }
    }

    public func template(_ id: String) -> DrawingTemplate? {
        templates.first { $0.id == id }
    }

    /// `base`, or `base 2`, `base 3`… when a template already has the name.
    public func uniqueName(_ base: String) -> String {
        let base = Self.trimmed(base)
        let taken = Set(templates.map { Self.trimmed($0.name) })
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    /// Adds `template` under a unique name. An id that can't be a file name sets `saveProblem` and adds nothing.
    public func add(_ template: DrawingTemplate) {
        var added = template
        added.name = uniqueName(template.name)
        guard persist(added) else { return }
        templates = Self.sorted(templates.filter { $0.id != added.id } + [added])
        saveProblem = nil
    }

    public func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveProblem = "A template needs a name."
            return
        }
        guard var renamed = template(id) else { return }
        guard !templates.contains(where: { $0.id != id && Self.trimmed($0.name) == trimmed }) else {
            saveProblem = "Another template already has that name."
            return
        }
        renamed.name = trimmed
        guard persist(renamed) else { return }
        templates = Self.sorted(templates.filter { $0.id != id } + [renamed])
        saveProblem = nil
    }

    public func remove(_ id: String) {
        guard let existing = template(id) else { return }
        if let folder {
            do throws(DrawingTemplateProblem) {
                try folder.remove(id, named: existing.name)
            } catch {
                saveProblem = error.message
                return
            }
        }
        templates.removeAll { $0.id == id }
        saveProblem = nil
    }

    private func persist(_ template: DrawingTemplate) -> Bool {
        guard let folder else {
            guard DrawingTemplateFolder.isUsable(template.id) else {
                saveProblem = "“\(template.name)” couldn't be saved: its id can't be a file name."
                return false
            }
            return true
        }
        do throws(DrawingTemplateProblem) {
            try folder.save(template)
            return true
        } catch {
            saveProblem = error.message
            return false
        }
    }

    private static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sorted(_ list: [DrawingTemplate]) -> [DrawingTemplate] {
        list.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
