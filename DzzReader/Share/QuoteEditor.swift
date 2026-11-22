import SwiftUI
import UIKit

/// The quote box: a UITextView whose keyboard carries a 完成 bar. SwiftUI's keyboard toolbar
/// often fails to appear inside a TabView; an input accessory view belongs to the text view
/// itself, so it shows every time the keyboard does.
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

        let bar = UIToolbar()
        bar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: "完成", primaryAction: UIAction { [weak view] _ in view?.resignFirstResponder() }),
        ]
        bar.sizeToFit()
        view.inputAccessoryView = bar
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
