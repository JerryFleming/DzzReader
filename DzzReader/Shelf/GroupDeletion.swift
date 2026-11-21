import SwiftUI

/// A whole-group delete waiting for the reader to confirm it.
struct GroupDeletion {
    let name: String
    let count: Int
    let message: String
    let perform: @MainActor () -> Void
}

extension View {
    /// Asks before deleting a group; `pending` is cleared either way.
    func confirmsGroupDeletion(_ pending: Binding<GroupDeletion?>) -> some View {
        confirmationDialog(
            pending.wrappedValue.map { "删除「\($0.name)」的全部 \($0.count) 项？" } ?? "",
            isPresented: Binding(get: { pending.wrappedValue != nil },
                                 set: { if !$0 { pending.wrappedValue = nil } }),
            titleVisibility: .visible,
            presenting: pending.wrappedValue
        ) { group in
            Button("删除", role: .destructive) { group.perform() }
            Button("取消", role: .cancel) {}
        } message: { group in
            Text(group.message)
        }
    }
}
