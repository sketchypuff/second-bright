import SwiftUI
import ServiceManagement
import SecondBrightCore

struct BrightnessPopover: View {
    @Bindable var controller: BrightnessController

    private static let presets: [Double] = [0, 25, 50, 100]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if controller.mode == .unavailable {
                Text("No external display connected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                slider
                presetRow
                if controller.mode == .software { softwareModeNote }
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 280)
        // While this is on screen the user is deliberately setting a level, so
        // the zero-brightness cursor wake must stay out of the way -- on a Mac
        // where the external monitor is the main display, this popover is itself
        // on the screen being blacked out.
        .onAppear { controller.setPopoverOpen(true) }
        .onDisappear { controller.setPopoverOpen(false) }
    }

    private var header: some View {
        HStack {
            Text(controller.mode == .unavailable ? "SecondBright" : controller.displayName)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            if controller.mode != .unavailable {
                Text("\(Int(controller.percent.rounded()))%")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var slider: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.min").foregroundStyle(.secondary)
            Slider(value: $controller.percent, in: 0...100)
            Image(systemName: "sun.max").foregroundStyle(.secondary)
        }
    }

    private var presetRow: some View {
        HStack(spacing: 6) {
            ForEach(Self.presets, id: \.self) { preset in
                Button("\(Int(preset))%") { controller.percent = preset }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// The user needs to know this is dimming the image rather than the backlight,
    /// because it behaves differently: it can't exceed 100% and it helps less with
    /// eye strain in a dark room.
    private var softwareModeNote: some View {
        Label(
            "This monitor won't accept backlight commands, so SecondBright is dimming the image instead.",
            systemImage: "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack {
            Toggle("Launch at login", isOn: launchAtLoginBinding)
                .toggleStyle(.checkbox)
                .font(.callout)
            Spacer()
            Button("Quit") {
                controller.shutdown()
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                try? enabled
                    ? SMAppService.mainApp.register()
                    : SMAppService.mainApp.unregister()
            }
        )
    }
}
