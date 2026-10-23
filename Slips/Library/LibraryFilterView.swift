import SlipsCore
import SwiftUI

/// Library filters: kind, business, sub-category, payment method, status, delivery state, checks, period.
struct LibraryFilterView: View {
    let profileId: UUID
    @Binding var filter: LibraryFilter
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var reference = ReferenceSnapshot()

    var body: some View {
        Form {
            Section {
                Picker("field.kind", selection: $filter.kind) {
                    Text("value.any").tag(Kind?.none)
                    ForEach(Kind.allCases, id: \.self) { Text($0.title).tag(Kind?.some($0)) }
                }
                Picker("field.business", selection: $filter.enterpriseId) {
                    Text("value.any").tag(UUID?.none)
                    ForEach(reference.enterprises) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Picker("field.subcategory", selection: $filter.subcategoryId) {
                    Text("value.any").tag(UUID?.none)
                    ForEach(reference.subcategories) { Text($0.displayName).tag(UUID?.some($0.id)) }
                }
                Picker("field.paymentMethod", selection: $filter.paymentMethodId) {
                    Text("value.any").tag(UUID?.none)
                    ForEach(reference.paymentMethods) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
            Section {
                Picker("field.status", selection: $filter.status) {
                    Text("value.any").tag(SlipStatus?.none)
                    Text("slipStatus.draft").tag(SlipStatus?.some(.draft))
                    Text("slipStatus.ready").tag(SlipStatus?.some(.ready))
                    Text("slipStatus.archived").tag(SlipStatus?.some(.archived))
                }
                Picker("field.delivery", selection: $filter.delivery) {
                    Text("value.any").tag(DeliveryState?.none)
                    Text("deliveryState.delivered").tag(DeliveryState?.some(.delivered))
                    Text("deliveryState.waiting").tag(DeliveryState?.some(.waiting))
                    Text("deliveryState.problem").tag(DeliveryState?.some(.problem))
                    Text("deliveryState.localOnly").tag(DeliveryState?.some(.localOnly))
                }
                Toggle("library.filter.warnings", isOn: $filter.withWarnings)
            }
            Section("library.filter.period") {
                DayField(day: $filter.from)
                    .labelsHidden()
                    .accessibilityLabel(Text("library.filter.from"))
                DayField(day: $filter.to)
                    .accessibilityLabel(Text("library.filter.to"))
            }
            Section {
                Button("library.clearFilters", role: .destructive) {
                    let search = filter.search
                    filter = LibraryFilter()
                    filter.search = search
                }
            }
        }
        .navigationTitle(Text("library.filters"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("action.done") { dismiss() } }
        }
        .task { reference = (try? model.reference.snapshot(profile: profileId)) ?? ReferenceSnapshot() }
    }
}
