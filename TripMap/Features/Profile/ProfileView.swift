import SwiftUI

struct ProfileView: View {
    @AppStorage("profile.displayName") private var displayName = ""
    @AppStorage("planning.baseCurrencyCode") private var baseCurrencyCode = SupportedCurrency.jpy.rawValue

    var body: some View {
        Form {
            Section("プロフィール") {
                TextField("表示名", text: $displayName, prompt: Text("あなたの名前"))
                LabeledContent("ホームタイムゾーン") {
                    Text(TimeZone.current.localizedName(for: .standard, locale: .current) ?? TimeZone.current.identifier)
                        .foregroundStyle(.secondary)
                }
            }

            Section("計画の既定値") {
                Picker("Base Currency", selection: $baseCurrencyCode) {
                    ForEach(SupportedCurrency.allCases) { currency in
                        Text(currency.label).tag(currency.rawValue)
                    }
                }
                Text("新しいTripの既定通貨です。既存Tripの通貨は変更しません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("旅行データ") {
                Text("Participantの旅行への割り当て、iCloud同期、バックアップは後続のマイルストーンで追加します。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Me")
    }
}
