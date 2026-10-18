import CoreLocation
import SwiftUI

struct RoutePlannerSheet: View {
    @Binding var start: CLLocationCoordinate2D?
    @Binding var end: CLLocationCoordinate2D?
    @Binding var isRouting: Bool
    var onBuild: () -> Void
    var onPlay: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onUseDrawn: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss
    private enum Field: Hashable { case distance, speed }
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            List {
                Section("Road route") {
                    Button("Use current pin / spoof as start") {
                        start = session.simulated ?? session.pin
                    }
                    Button("Use current pin as end") {
                        end = session.pin
                    }
                    LabeledContent("Start") {
                        Text(coordText(start)).font(.caption.monospaced())
                    }
                    LabeledContent("End") {
                        Text(coordText(end)).font(.caption.monospaced())
                    }
                    Button {
                        onBuild()
                    } label: {
                        if isRouting {
                            ProgressView()
                        } else {
                            Label("Build walk/drive route on roads", systemImage: "road.lanes")
                        }
                    }
                    .disabled(isRouting)
                }

                Section("Distanza e velocità") {
                    Toggle("Percorri il tracciato una volta", isOn: $session.entireRoute)
                    if !session.entireRoute {
                        HStack {
                            Text("Chilometri totali")
                            TextField("km", value: $session.routeDistanceKm, format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                                .focused($focusedField, equals: .distance)
                                .accessibilityLabel("Chilometri totali")
                        }
                    }
                    HStack {
                        Text("Velocità km/h")
                        TextField("km/h", value: $session.speedKmh, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                            .focused($focusedField, equals: .speed)
                            .accessibilityLabel("Velocità in chilometri orari")
                    }
                }
                Section("Play / draw / GPX") {
                    Button {
                        onUseDrawn()
                    } label: {
                        Label("Use drawn path from map", systemImage: "pencil.tip")
                    }
                    Button(action: onPlay) {
                        Label("Follow route", systemImage: "play.fill")
                    }
                    Button(action: onImportGPX) {
                        Label("Import GPX", systemImage: "square.and.arrow.down")
                    }
                    Button(action: onExportGPX) {
                        Label("Export GPX", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    Text("MapKit calcola strade o cammini quando disponibili. La velocità è quella impostata; il conteggio avanza dopo l’esito del servizio. Per una distanza maggiore del tracciato viene invertita la marcia agli estremi.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onSubmit { focusedField = nil }
            .navigationTitle("Routes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(focusedField == nil ? "Done" : "Fine") {
                        if focusedField != nil { focusedField = nil }
                        else { dismiss() }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fine") { focusedField = nil }
                }
            }
        }
    }

    private func coordText(_ c: CLLocationCoordinate2D?) -> String {
        guard let c else { return "—" }
        return String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }
}
