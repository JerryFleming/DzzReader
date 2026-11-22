import SwiftUI
import UIKit

/// The quote box: a UITextView whose keyboard carries the 完成 bar (`UIToolbar.doneBar`).
struct QuoteEditor: UIViewRepresentable {
    @Binding var text: String
    /// True while the box has the keyboard; set it to false to put the keyboard away.
    @Binding var editing: Bool

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.text = text
        view.accessibilityIdentifier = "quoteEditor"

        view.inputAccessoryView = UIToolbar.doneBar { [weak view] in view?.resignFirstResponder() }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        if !editing && view.isFirstResponder { view.resignFirstResponder() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: QuoteEditor
        init(_ parent: QuoteEditor) { self.parent = parent }

        func textViewDidChange(_ view: UITextView) { parent.text = view.text }
        func textViewDidBeginEditing(_ view: UITextView) { parent.editing = true }
        func textViewDidEndEditing(_ view: UITextView) { parent.editing = false }
    }
}
