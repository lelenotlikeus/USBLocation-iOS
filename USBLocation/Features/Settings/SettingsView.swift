import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var tunnelIP = TunnelConfig.targetIP
    @State private var manualLatitude = 41.9028
    @State private var manualLongitude = 12.4964
    @AppStorage("usblocation.instantTeleport") private var instantTeleport = false
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @Environment(\.scenePhase) private var scenePhase
    private enum Field: Hashable { case tunnel, latitude, longitude }
    @FocusState private var focusedField: Field?

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(pairing.hasPairingFile ? "RPPairing file installed" : "No pairing file")
                    } icon: {
                        Image(systemName: pairing.hasPairingFile ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pairing.hasPairingFile ? USBLocationTheme.statusGood : USBLocationTheme.statusWarn)
                    }

                    if supportsOnDevicePairing {
                        Button {
                            showPairOnDevice = true
                        } label: {
                            Label("Pair on this iPhone", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }

                    Button("Import RPPairing file…") { showImporter = true }
                    Button("Paste RPPairing from clipboard") {
                        do {
                            try pairing.importPairingFromClipboard()
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    }
                    if pairing.hasPairingFile {
                        ShareLink(item: pairing.pairingURL) {
                            Label("Esporta pairing per StikDebug", systemImage: "square.and.arrow.up")
                        }
                        Button("Remove pairing file", role: .destructive) {
                            try? pairing.removePairing()
                        }
                    }
                } header: {
                    Text("Developer pairing")
                } footer: {
                    Text(supportsOnDevicePairing
                         ? "On iOS 27, use Pair on this iPhone — no computer. USBLocation advertises a pairable host; confirm the 6-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host. On older iOS, import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). LiveContainer: enable Fix File Picker on USBLocation, or use Paste / Share → LiveContainer → USBLocation."
                         : "Import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). If the file picker fails (common in LiveContainer), enable Fix File Picker on the app, share the file into LiveContainer → USBLocation, or copy the plist and use Paste.")
                }

                Section {
                    TextField("Device tunnel IP", text: $tunnelIP)
                        .focused($focusedField, equals: .tunnel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            TunnelConfig.setTargetIP(tunnelIP)
                            focusedField = nil
                        }
                    LabeledContent("Status") {
                        Text(LocalDevVPN.isConnected ? "Connected" : "Not connected")
                            .foregroundStyle(LocalDevVPN.isConnected ? USBLocationTheme.statusGood : USBLocationTheme.statusWarn)
                    }
                    Button("Save tunnel IP") {
                        TunnelConfig.setTargetIP(tunnelIP)
                    }
                    Button {
                        if localDevVPNInstalled {
                            LocalDevVPN.openInstalled()
                        } else {
                            LocalDevVPN.openAppStore()
                        }
                    } label: {
                        Label(
                            localDevVPNInstalled ? "Open LocalDevVPN" : "Get LocalDevVPN (App Store)",
                            systemImage: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill"
                        )
                    }
                } header: {
                    Text("Tunnel")
                } footer: {
                    Text("Connect LocalDevVPN before teleporting. Default tunnel IP is 10.7.0.1. Start a spoof on Wi‑Fi first; it can keep working on cellular afterward.")
                }

                Section("Coordinate e teletrasporto") {
                    HStack {
                        Text("Latitudine")
                        TextField("Latitudine", value: $manualLatitude, format: .number.precision(.fractionLength(0...7)))
                            .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .latitude)
                            .accessibilityLabel("Latitudine di destinazione")
                    }
                    HStack {
                        Text("Longitudine")
                        TextField("Longitudine", value: $manualLongitude, format: .number.precision(.fractionLength(0...7)))
                            .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .longitude)
                            .accessibilityLabel("Longitudine di destinazione")
                    }
                    Button("Teletrasporta alle coordinate") {
                        session.teleport(to: .init(latitude: manualLatitude, longitude: manualLongitude), pairing: pairing)
                        dismiss()
                    }.disabled(session.isBusy || !pairing.hasPairingFile)
                    Toggle("Teletrasporto immediato al tocco", isOn: $instantTeleport)
                    Text("Se attivo, un tocco sulla mappa invia subito la posizione all’iPhone. Il disegno dei percorsi aggiunge invece tappe.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Servizi developer e reset") {
                    Link("StikDebug: preparazione DDI sul telefono", destination: URL(string: "https://github.com/StikDebug/StikDebug")!)
                    Text("Se il servizio DVT non è disponibile, prepara la Developer Disk Image con StikDebug. Puoi importare lì il pairing esportato da questa app. Il file contiene credenziali: non pubblicarlo.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Invia Reset GPS", role: .destructive) { session.stop(pairing: pairing) }
                        .disabled(!pairing.hasPairingFile)
                    Text("Reset invia la fine simulazione; non certifica il fix GPS reale.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Text("Preferiti e pairing restano nel telefono. MapKit invia ad Apple le richieste di mappe, ricerca e percorsi. Nessuna telemetria aggiunta.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Engine", value: "idevice DVT location simulation")
                    Text("USBLocation Mobile deriva da Locus 1.0.2 (MIT), di ChrisMack32 e collaboratori. Backend idevice (MIT). Nessuna affiliazione agli autori originali o ad Apple.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(focusedField == nil ? "Done" : "Fine") {
                        TunnelConfig.setTargetIP(tunnelIP)
                        if focusedField != nil { focusedField = nil }
                        else { dismiss() }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fine") { focusedField = nil }
                }
            }
            .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
            .sheet(isPresented: $showPairOnDevice) {
                PairOnDeviceView()
                    .environmentObject(pairing)
            }
            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
        }
    }
}

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Favorites") {
                    if session.favorites.isEmpty {
                        Text("Star a pin from the map to save it.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.favorites) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeFavorite(place)
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                                Button {
                                    placeToRename = place
                                    renameText = place.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                    }
                }

                Section("Recents") {
                    if session.recents.isEmpty {
                        Text("Teleports show up here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.recents) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeRecent(place)
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Places")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Favorite", isPresented: Binding(
                get: { placeToRename != nil },
                set: { if !$0 { placeToRename = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {
                    placeToRename = nil
                }
                Button("Save") {
                    if let place = placeToRename {
                        session.renameFavorite(place, to: renameText)
                    }
                    placeToRename = nil
                }
            } message: {
                Text("Choose a name you’ll recognize later.")
            }
        }
    }

    private func placeButton(_ place: SavedPlace) -> some View {
        Button {
            session.teleport(to: place.coordinate, pairing: pairing)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
