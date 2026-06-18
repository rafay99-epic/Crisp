import SwiftUI
import CrispCore

struct OptionsCard: View {
    @Bindable var model: CleanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How much to cut").font(.headline)
                Picker("", selection: $model.strength) {
                    ForEach(Strength.allCases) { Text($0.pickerLabel).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                HStack(alignment: .firstTextBaseline) {
                    Text(model.strength.detail)
                        .font(.callout).foregroundStyle(.secondary)
                    if model.strength == .custom {
                        Spacer()
                        SettingsLink { Text("Adjust\u{2026}") }
                            .controlSize(.small)
                    }
                }
            }
            Divider()
            Toggle(isOn: $model.removeFillers) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove filler words").font(.headline)
                    Text("um, uh, hmm, erm, aww\u{2026}").font(.callout).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .disabled(model.isRunning)
    }
}
