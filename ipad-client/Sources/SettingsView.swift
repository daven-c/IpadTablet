import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var locked = TabletSettings.aspectRatioLocked
    @State private var ratio = TabletSettings.aspectRatio
    @State private var width = TabletSettings.activeWidth
    @State private var height = TabletSettings.activeHeight
    @State private var smoothing = TabletSettings.smoothing
    @State private var positionLocked = TabletSettings.positionLocked

    var body: some View {
        NavigationStack {
            Form {
                Section("Active area (iPad points)") {
                    HStack {
                        Text("Width")
                        Spacer()
                        TextField("Width", value: $width, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    .onChange(of: width) { _, newValue in
                        if locked, ratio > 0 { height = newValue / ratio }
                    }

                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("Height", value: $height, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    .onChange(of: height) { _, newValue in
                        if locked, newValue > 0 { width = newValue * ratio }
                    }

                    Text("Smaller area = less physical movement needed to reach the full range (more sensitive). Capped at the full screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Aspect ratio") {
                    Toggle("Lock ratio", isOn: $locked)
                    HStack {
                        Text("Ratio (W:H)")
                        Spacer()
                        TextField("Ratio", value: $ratio, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    .onChange(of: ratio) { _, newValue in
                        if locked, newValue > 0 { height = width / newValue }
                    }
                    Text("With the ratio locked, edit just Width or Height above — the other follows automatically. Example: 1.4 feels squarer than the screen's native rectangle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Smoothing") {
                    Slider(value: $smoothing, in: 0...0.95, step: 0.05)
                    Text(smoothing == 0
                         ? "Off — raw touch data, lowest latency."
                         : String(format: "%.0f%% — trades some responsiveness for less jitter. A fresh stroke always starts exactly at contact point regardless.", smoothing * 100))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Lock position", isOn: $positionLocked)
                    Text("Prevents dragging the active area on screen with a finger. Also toggleable from the lock icon next to the gear on the main screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Recenter active area") {
                        TabletSettings.offsetX = 0
                        TabletSettings.offsetY = 0
                        TabletSettings.notifyChanged()
                    }
                    Text("Drag the dashed outline on screen to move the active area anywhere; this just puts it back in the middle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Reset to full screen", role: .destructive) {
                        let screen = UIScreen.main.bounds.size
                        width = Double(max(screen.width, screen.height))
                        height = Double(min(screen.width, screen.height))
                        ratio = width / height
                        locked = true
                        smoothing = 0
                        TabletSettings.offsetX = 0
                        TabletSettings.offsetY = 0
                    }
                }
            }
            .navigationTitle("Tablet Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                }
            }
        }
    }

    private func save() {
        TabletSettings.aspectRatioLocked = locked
        TabletSettings.aspectRatio = max(ratio, 0.01)
        TabletSettings.activeWidth = max(width, 1)
        TabletSettings.activeHeight = max(height, 1)
        TabletSettings.smoothing = smoothing
        TabletSettings.positionLocked = positionLocked
        TabletSettings.notifyChanged()
        dismiss()
    }
}
