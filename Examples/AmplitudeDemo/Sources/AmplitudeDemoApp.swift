import Amplitude
import SwiftUI

private enum DemoStyle {
    static let blue = Color(hex: 0x1E61F0)
    static let navy = Color(hex: 0x0B1226)
    static let canvas = Color(hex: 0xF3F5F9)
}

private struct Product: Identifiable {
    let id: String
    let name: String
    let price: Double

    static let catalog = [
        Product(id: "analytics-hoodie", name: "Analytics Hoodie", price: 59),
        Product(id: "experiment-mug", name: "Experiment Mug", price: 18),
        Product(id: "session-replay-cap", name: "Session Replay Cap", price: 25)
    ]
}

private struct DemoEvent: Identifiable {
    let id = UUID()
    let eventType: String
    let time: Date
    let userProperties: String?
}

private struct SessionDetails {
    let deviceId: String
    let userId: String?
    let sessionId: String
}

@MainActor
private final class AmplitudeService: ObservableObject {
    let amp: Amplitude
    let apiKeyStatus: String
    let hasAPIKey: Bool

    @Published private(set) var session = SessionDetails(deviceId: "—", userId: nil, sessionId: "—")
    @Published private(set) var events: [DemoEvent] = []
    @Published private(set) var eventCount = 0
    @Published var sdkReportedOptOut = false

    init() {
        let providedKey = ProcessInfo.processInfo.environment["AMPLITUDE_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        hasAPIKey = !providedKey.isEmpty
        apiKeyStatus = providedKey.isEmpty ? "local-only" : "configured ••••\(providedKey.suffix(4))"

        let amplitude = Amplitude.instance()
        amp = amplitude
        sdkReportedOptOut = amplitude.optOut
        amplitude.eventUploadThreshold = 1
        amplitude.eventUploadPeriodSeconds = 5
        amplitude.defaultTracking.sessions = true

        let middleware = AMPBlockMiddleware { [weak self] payload, next in
            let eventType = payload.event["event_type"] as? String ?? "Unknown Event"
            let userProperties = Self.userPropertiesDescription(from: payload.event["user_properties"])
            let event = DemoEvent(eventType: eventType, time: Date(), userProperties: userProperties)

            DispatchQueue.main.async {
                self?.append(event)
                next(payload)
            }
        }
        amplitude.addEventMiddleware(middleware)
        amplitude.initializeApiKey(providedKey.isEmpty ? "local-only" : providedKey)
        refreshSession()
    }

    func refreshSession() {
        session = SessionDetails(
            deviceId: amp.getDeviceId(),
            userId: amp.userId,
            sessionId: String(amp.getSessionId())
        )
    }

    func updatePrivacy(sharing: Bool) {
        amp.optOut = !sharing
        let sdkOptOut = amp.optOut
        sdkReportedOptOut = sdkOptOut
    }

    func rereadPrivacy() {
        sdkReportedOptOut = amp.optOut
    }

    private func append(_ event: DemoEvent) {
        eventCount += 1
        events.insert(event, at: 0)
        refreshSession()
        if events.count > 50 {
            events.removeLast(events.count - 50)
        }
    }

    private static func userPropertiesDescription(from value: Any?) -> String? {
        guard let userProperties = value as? [String: Any] else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: userProperties, options: [.sortedKeys, .fragmentsAllowed]),
              let description = String(data: data, encoding: .utf8) else {
            return String(describing: userProperties)
        }
        return description
    }
}

@main
private struct AmplitudeDemoApp: App {
    @StateObject private var service = AmplitudeService()

    var body: some Scene {
        WindowGroup {
            DemoView(service: service)
        }
    }
}

private struct DemoView: View {
    @ObservedObject private var service: AmplitudeService
    @State private var sharing: Bool
    @State private var userIDInput = ""
    @State private var selectedPlan = "free"
    @State private var cart: [String: Int] = [:]

    init(service: AmplitudeService) {
        _service = ObservedObject(wrappedValue: service)
        _sharing = State(initialValue: !service.amp.optOut)
    }

    private var cartItemCount: Int {
        cart.values.reduce(0, +)
    }

    private var cartTotal: Double {
        Product.catalog.reduce(0) { total, product in
            total + product.price * Double(cart[product.id, default: 0])
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if !service.hasAPIKey {
                    Text("No API key — events are logged locally only")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: 0x795800))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0xFFF1C2), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("apiKey.missingBanner")
                }

                sessionCard
                shopCard
                identifyCard
                privacyCard
                eventLogCard
            }
            .padding(18)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(DemoStyle.canvas.ignoresSafeArea())
        .tint(DemoStyle.blue)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Amplitude Demo")
                .font(.system(size: 28, weight: .bold))
                .accessibilityIdentifier("header.title")
            Text("Legacy iOS SDK 8.22.2 · local build")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.76))
                .accessibilityIdentifier("header.subtitle")
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DemoStyle.navy, in: RoundedRectangle(cornerRadius: 18))
    }

    private var sessionCard: some View {
        card(title: "Session", identifier: "session.title") {
            sessionRow("Device ID", value: service.session.deviceId, identifier: "session.deviceId")
            sessionRow("User ID", value: service.session.userId ?? "anonymous", identifier: "session.userId")
            sessionRow("Session ID", value: service.session.sessionId, identifier: "session.sessionId")
            sessionRow("API key", value: service.apiKeyStatus, identifier: "session.apiKey")
        }
    }

    private var shopCard: some View {
        card(title: "Shop", identifier: "shop.title") {
            ForEach(Product.catalog) { product in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product.name)
                            .font(.system(.body, weight: .semibold))
                            .accessibilityIdentifier("product.name.\(product.id)")
                        Text(currency(product.price))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("product.price.\(product.id)")
                    }
                    Spacer(minLength: 4)
                    Button("View") {
                        logProductEvent("Product Viewed", product: product)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("product.view.\(product.id)")
                    Button("Add") {
                        cart[product.id, default: 0] += 1
                        logProductEvent("Add To Cart", product: product)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("product.add.\(product.id)")
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Text("Cart: \(cartItemCount) items")
                    .accessibilityIdentifier("cart.count")
                Spacer()
                Text("Total: \(currency(cartTotal))")
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("cart.total")
            }

            Button(action: checkout) {
                Text("Checkout")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(cartItemCount == 0)
            .accessibilityIdentifier("cart.checkout")
        }
    }

    private var identifyCard: some View {
        card(title: "Identify", identifier: "identify.title") {
            TextField("User ID", text: $userIDInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("identify.userId")

            Button("Log in") {
                service.amp.setUserId(userIDInput.isEmpty ? nil : userIDInput)
                service.refreshSession()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("identify.login")

            Picker("Plan", selection: $selectedPlan) {
                ForEach(["free", "pro", "enterprise"], id: \.self) { plan in
                    Text(plan.capitalized)
                        .tag(plan)
                        .accessibilityIdentifier("identify.plan.\(plan)")
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("identify.planPicker")

            Button("Set plan") {
                let identify = AMPIdentify()
                identify.set("plan", value: selectedPlan as NSString)
                service.amp.identify(identify)
                service.refreshSession()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("identify.setPlan")

            Button("Log out", role: .destructive) {
                service.amp.setUserId(nil)
                service.amp.regenerateDeviceId()
                service.refreshSession()
            }
            .accessibilityIdentifier("identify.logout")
        }
    }

    private var privacyCard: some View {
        card(title: "Privacy", identifier: "privacy.title") {
            Toggle(isOn: $sharing) {
                Text("Share usage analytics")
                    .accessibilityIdentifier("privacy.label")
            }
            .accessibilityIdentifier("privacy.toggle")
            .onChange(of: sharing) { _, newValue in
                service.updatePrivacy(sharing: newValue)
                service.refreshSession()
            }

            Text("SDK reports optOut = \(service.sdkReportedOptOut ? "true" : "false")")
                .accessibilityIdentifier("privacy.sdkOptOut")

            if service.sdkReportedOptOut != !sharing {
                Text("⚠︎ SDK state doesn't match your choice (expected optOut = \(!sharing ? "true" : "false"))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.red)
                    .accessibilityIdentifier("privacy.mismatch")
            } else {
                Text("✓ In sync")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.green)
                    .accessibilityIdentifier("privacy.inSync")
            }

            Button("Re-read") {
                service.rereadPrivacy()
                service.refreshSession()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("privacy.reread")
        }
    }

    private var eventLogCard: some View {
        card(title: "Event log · \(service.eventCount)", identifier: "log.title") {
            Button("Flush now") {
                service.amp.uploadEvents()
                service.refreshSession()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("log.flush")

            Text("Total events: \(service.eventCount)")
                .font(.subheadline.weight(.medium))
                .accessibilityIdentifier("log.count")

            if service.events.isEmpty {
                Text("Waiting for SDK events…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("log.empty")
            } else {
                ForEach(service.events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(event.eventType)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(event.time.formatted(date: .omitted, time: .standard))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if let userProperties = event.userProperties {
                            Text(userProperties)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 5)
                    .accessibilityIdentifier("log.event.\(event.id.uuidString)")
                }
            }
        }
    }

    private func card<Content: View>(
        title: String,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(.title3, weight: .bold))
                .foregroundStyle(DemoStyle.navy)
                .accessibilityIdentifier(identifier)
            content()
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sessionRow(_ label: String, value: String, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("\(identifier).label")
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .accessibilityIdentifier(identifier)
        }
    }

    private func logProductEvent(_ eventType: String, product: Product) {
        service.amp.logEvent(eventType, withEventProperties: [
            "product_id": product.id,
            "name": product.name,
            "price": product.price
        ])
        service.refreshSession()
    }

    private func checkout() {
        guard cartItemCount > 0 else { return }
        let orderID = String(UUID().uuidString.prefix(8))
        service.amp.logEvent("Order Completed", withEventProperties: [
            "order_id": orderID,
            "item_count": cartItemCount,
            "total": cartTotal
        ])

        for product in Product.catalog {
            let quantity = cart[product.id, default: 0]
            guard quantity > 0 else { continue }
            let revenue = AMPRevenue()
            revenue.setProductIdentifier(product.id)
            revenue.setPrice(NSNumber(value: product.price))
            revenue.setQuantity(quantity)
            revenue.setRevenueType("purchase")
            service.amp.logRevenueV2(revenue)
        }

        cart.removeAll()
        service.refreshSession()
    }

    private func currency(_ amount: Double) -> String {
        "$\(Int(amount))"
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
