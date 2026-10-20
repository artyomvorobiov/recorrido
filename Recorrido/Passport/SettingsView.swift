import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.contentLanguage, store: AppGroup.defaults) private var contentLanguage = "auto"
    @AppStorage(SettingsKey.speechRate, store: AppGroup.defaults) private var speechRate = 1.0
    @AppStorage(SettingsKey.autoPlay, store: AppGroup.defaults) private var autoPlay = true
    @AppStorage(SettingsKey.backgroundTracking, store: AppGroup.defaults) private var backgroundTracking = true
    @AppStorage(SettingsKey.arrivalNotifications, store: AppGroup.defaults) private var arrivalNotifications = true
    @State private var confirmsErase = false

    var body: some View {
        Form {
            Section {
                Picker("Language of routes", selection: $contentLanguage) {
                    Text("Automatic").tag("auto")
                    Text(verbatim: "Русский").tag("ru")
                    Text(verbatim: "English").tag("en")
                }
            } footer: {
                Text("Catalog texts and Wikipedia descriptions for new routes.")
            }

            Section("Audio guide") {
                Toggle("Read the story on arrival", isOn: $autoPlay)
                VStack(alignment: .leading) {
                    Text("Speed")
                    Slider(value: $speechRate, in: 0.7...1.4, step: 0.1) {
                        Text("Speed")
                    } minimumValueLabel: {
                        Image(systemName: "tortoise")
                    } maximumValueLabel: {
                        Image(systemName: "hare")
                    }
                }
            }

            Section {
                Toggle("Follow the walk in the background", isOn: $backgroundTracking)
                Toggle("Notify when I reach a stop", isOn: $arrivalNotifications)
            } header: {
                Text("During a walk")
            } footer: {
                Text("Location is used only while a walk is in progress, to show where you are and to notice arrivals. It never leaves the phone.")
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Link(destination: AppConfig.projectURL) {
                    Label("Project page", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Text("Maps and paths: Apple Maps. Photos and generated descriptions: Wikipedia and Wikimedia Commons, CC BY-SA 4.0.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if !AppGroup.isAvailable {
                    Text("The app group is not set up, so the widget shows the route of the day only. See README.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button("Erase my routes and passport", role: .destructive) {
                    confirmsErase = true
                }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: contentLanguage) { _, _ in
            model.reloadCatalog()
        }
        .confirmationDialog("Erase everything?", isPresented: $confirmsErase, titleVisibility: .visible) {
            Button("Erase", role: .destructive) {
                model.trip.end()
                model.library.eraseEverything()
            }
        } message: {
            Text("Your routes, bookmarks and stamps will be deleted from this iPhone.")
        }
    }
}
