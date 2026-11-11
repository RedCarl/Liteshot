import AppKit

@MainActor
final class EditorDocument {
    private(set) var annotations: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    var onChange: (() -> Void)?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func add(_ annotation: Annotation) {
        mutate { $0.append(annotation) }
    }

    func replace(_ annotation: Annotation) {
        mutate { annotations in
            guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
            annotations[index] = annotation
        }
    }

    func remove(id: UUID) {
        mutate { $0.removeAll { $0.id == id } }
    }

    func bringForward(id: UUID) {
        mutate { annotations in
            guard let index = annotations.firstIndex(where: { $0.id == id }), index < annotations.count - 1 else { return }
            annotations.swapAt(index, index + 1)
        }
    }

    func sendBackward(id: UUID) {
        mutate { annotations in
            guard let index = annotations.firstIndex(where: { $0.id == id }), index > 0 else { return }
            annotations.swapAt(index, index - 1)
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = previous
        onChange?()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
        onChange?()
    }

    private func mutate(_ block: (inout [Annotation]) -> Void) {
        let before = annotations
        block(&annotations)
        guard annotations != before else { return }
        undoStack.append(before)
        if undoStack.count > 80 {
            undoStack.removeFirst(undoStack.count - 80)
        }
        redoStack.removeAll()
        onChange?()
    }
}
