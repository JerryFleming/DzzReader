import SwiftUI
import UIKit

extension UIToolbar {
    /// The 完成 bar shown above the keyboard. SwiftUI's `.keyboard` toolbar often fails to appear
    /// inside a TabView; an input accessory view belongs to its text view, so it always shows.
    static func doneBar(_ action: @escaping () -> Void) -> UIToolbar {
        let bar = UIToolbar()
        bar.items = [
            UIBarButtonItem(systemItem: .flexibleSpace),
            UIBarButtonItem(title: "完成", primaryAction: UIAction { _ in action() }),
        ]
        bar.sizeToFit()
        return bar
    }
}

/// A one-line text field whose keyboard carries the 完成 bar. Return and 完成 both call `onDone`,
/// which decides how the keyboard goes away (usually by setting `focused` to false).
struct DoneBarTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    /// Mirrors first-responder status both ways: true raises the keyboard, false puts it away.
    @Binding var focused: Bool
    var returnKey: UIReturnKeyType = .default
    let onDone: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.text = text
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = returnKey
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.inputAccessoryView = UIToolbar.doneBar { [weak coordinator = context.coordinator] in
            coordinator?.parent.onDone()
        }
        field.addAction(UIAction { [weak field, weak coordinator = context.coordinator] _ in
            coordinator?.parent.text = field?.text ?? ""
        }, for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        // Deferred: becoming or resigning first responder during a SwiftUI update is not allowed.
        if focused != field.isFirstResponder {
            DispatchQueue.main.async {
                guard context.coordinator.parent.focused != field.isFirstResponder else { return }
                if context.coordinator.parent.focused { field.becomeFirstResponder() } else { field.resignFirstResponder() }
            }
        }
    }

    /// Take the offered width but only one line of height; a bare UITextField fills both.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView field: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? field.intrinsicContentSize.width, height: field.intrinsicContentSize.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DoneBarTextField
        init(_ parent: DoneBarTextField) { self.parent = parent }

        func textFieldDidBeginEditing(_ field: UITextField) { if !parent.focused { parent.focused = true } }
        func textFieldDidEndEditing(_ field: UITextField) { if parent.focused { parent.focused = false } }
        func textFieldShouldReturn(_ field: UITextField) -> Bool { parent.onDone(); return false }
    }
}

/// A URL box that wraps onto as many lines as the text needs, with the 完成 bar on its keyboard.
/// Return and 完成 both put the keyboard away: a URL has no line breaks.
struct DoneBarURLField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.isScrollEnabled = false   // grow with the text instead of scrolling inside the row
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0   // line up with the other Form rows
        view.keyboardType = .URL
        view.autocapitalizationType = .none
        view.autocorrectionType = .no
        view.returnKeyType = .done
        view.text = text
        view.inputAccessoryView = UIToolbar.doneBar { [weak view] in view?.resignFirstResponder() }

        let label = context.coordinator.placeholder
        label.text = placeholder
        label.font = view.font
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .placeholderText
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor),
        ])
        label.isHidden = !text.isEmpty
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text { view.text = text }
        context.coordinator.placeholder.isHidden = !text.isEmpty
        view.isEditable = context.environment.isEnabled   // honour .disabled(_:)
        view.textColor = context.environment.isEnabled ? .label : .secondaryLabel
    }

    /// The offered width, and as many lines of height as the text wraps to.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let fitted = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitted.height, view.font?.lineHeight ?? 22))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: DoneBarURLField
        let placeholder = UILabel()
        init(_ parent: DoneBarURLField) { self.parent = parent }

        func textViewDidChange(_ view: UITextView) {
            parent.text = view.text
            placeholder.isHidden = !view.text.isEmpty
        }

        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text.contains("\n") else { return true }
            if text == "\n" { view.resignFirstResponder(); return false }   // the return key
            // Pasted text: keep it on one line.
            view.replace(view.textRange(from: view.position(from: view.beginningOfDocument, offset: range.location)!,
                                        to: view.position(from: view.beginningOfDocument, offset: range.location + range.length)!)!,
                         withText: text.replacingOccurrences(of: "\n", with: ""))
            return false
        }
    }
}
