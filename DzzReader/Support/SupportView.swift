import SwiftUI

/// 支持: voluntary tips. Everything in the app stays free; a tip unlocks nothing.
struct SupportView: View {
    @State private var jar = TipJar()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.pink)
                        Text("本应用完全免费，没有广告。若它对你有所帮助，欢迎随喜支持，帮助它继续维护。")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(Tip.allCases) { tip in
                        row(tip)
                    }
                } footer: {
                    if jar.loaded && jar.products.isEmpty {
                        Text("暂时无法连接 App Store，请稍后再试。")
                    } else {
                        Text("自愿支持，不会解锁任何功能。可重复支持。")
                    }
                }
            }
            .navigationTitle("支持")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await jar.load() }
        .alert("感恩支持", isPresented: Binding(get: { jar.status == .thanked }, set: { if !$0 { jar.status = .idle } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text("谢谢你的随喜，愿你吉祥安乐。")
        }
        .alert("未能完成支付", isPresented: Binding(get: { failure != nil }, set: { if !$0 { jar.status = .idle } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private var failure: String? {
        if case .failed(let message) = jar.status { message } else { nil }
    }

    private func row(_ tip: Tip) -> some View {
        let product = jar.products[tip]
        let busy = jar.status == .purchasing(tip)
        return Button {
            Task { await jar.buy(tip) }
        } label: {
            HStack {
                Label(tip.title, systemImage: tip.symbol)
                    .foregroundStyle(.primary)
                Spacer()
                if busy {
                    ProgressView()
                } else {
                    Text(product?.displayPrice ?? tip.fallbackPrice)
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
            }
        }
        .disabled(product == nil || isPurchasing)
        .accessibilityIdentifier("tip-\(tip.title)")
    }

    private var isPurchasing: Bool {
        if case .purchasing = jar.status { true } else { false }
    }
}
