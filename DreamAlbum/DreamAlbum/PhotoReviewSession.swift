import Foundation

/// Device-local decisions. No PhotoKit identifiers enter a dream or its cloud backup.
struct PhotoReviewSession: Codable, Equatable {
    struct Decision: Codable, Equatable {
        var id: String
        var wasReviewed: Bool
        var wasPending: Bool
    }
    private(set) var queue: [String] = []
    private(set) var reviewed: Set<String> = []
    private(set) var pendingDeletion: Set<String> = []
    private(set) var history: [Decision] = []

    var currentID: String? { queue.first { !reviewed.contains($0) } }
    var completedCount: Int { queue.reduce(0) { $0 + (reviewed.contains($1) ? 1 : 0) } }

    mutating func start(_ ids: [String], restart: Bool = false) {
        if !restart, !queue.isEmpty, currentID != nil { return }
        queue = Array(NSOrderedSet(array: ids)) as? [String] ?? []
        reviewed = []
        history = []
    }

    /// Change scope without losing decisions from today, another day or another
    /// album. Undo remains scoped to the queue currently visible to the user.
    mutating func resume(_ ids: [String]) {
        queue = Array(NSOrderedSet(array: ids)) as? [String] ?? []
        let active = Set(queue)
        history.removeAll { !active.contains($0.id) }
    }

    mutating func restartScope(_ ids: [String]) {
        resume(ids)
        reviewed.subtract(queue)
        history = []
    }

    mutating func decide(_ id: String, delete: Bool) {
        guard !reviewed.contains(id) || pendingDeletion.contains(id) != delete else { return }
        history.append(Decision(id: id, wasReviewed: reviewed.contains(id), wasPending: pendingDeletion.contains(id)))
        reviewed.insert(id)
        if delete { pendingDeletion.insert(id) } else { pendingDeletion.remove(id) }
    }

    mutating func undo() {
        guard let decision = history.popLast() else { return }
        if decision.wasReviewed { reviewed.insert(decision.id) } else { reviewed.remove(decision.id) }
        if decision.wasPending { pendingDeletion.insert(decision.id) } else { pendingDeletion.remove(decision.id) }
    }

    mutating func unmark(_ id: String) {
        pendingDeletion.remove(id)
        // A later undo must never silently reinstate a cancelled deletion.
        history.removeAll { $0.id == id }
    }

    mutating func clearPending() {
        pendingDeletion.removeAll()
        history.removeAll()
    }

    mutating func removeDeleted(_ ids: Set<String>) {
        queue.removeAll { ids.contains($0) }
        reviewed.subtract(ids)
        pendingDeletion.subtract(ids)
        history.removeAll { ids.contains($0.id) }
    }

    mutating func reconcile(availableIDs: Set<String>) {
        removeDeleted(Set(queue).union(reviewed).union(pendingDeletion).union(history.map(\.id)).subtracting(availableIDs))
    }
}
