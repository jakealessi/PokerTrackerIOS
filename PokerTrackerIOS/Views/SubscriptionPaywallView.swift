//
//  SubscriptionPaywallView.swift
//  PokerTrackerIOS
//

import SwiftUI
import StoreKit

struct SubscriptionPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var subscriptionStore: SubscriptionStore
    @EnvironmentObject var settingsStore: SettingsStore
    @State private var activeTask: Task<Void, Never>?
    @State private var didAttemptPurchase = false

    var title: String = "Premium"
    var subtitle: String? = "Unlock unlimited AI Session Crafter, unlimited Odds Calculator, and all stats charts."

    private var purchaseButtonTitle: String {
        if subscriptionStore.proMonthlyProduct?.subscription?.introductoryOffer?.paymentMode == .freeTrial {
            return "Start Free Trial"
        }
        return "Subscribe Now"
    }

    private var purchaseFooterText: String? {
        guard let product = subscriptionStore.proMonthlyProduct else { return nil }
        return subscriptionStore.purchaseFooterText(for: product)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.accent)
                    Text(title)
                        .font(.title2.weight(.bold))
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 10) {
                    paywallFeature(icon: "sparkles", text: "Unlimited AI session logging")
                    paywallFeature(icon: "percent", text: "Unlimited odds calculator")
                    paywallFeature(icon: "chart.bar.fill", text: "All stats charts and breakdowns")
                }
                .padding(.horizontal, 32)

                if subscriptionStore.proMonthlyProduct == nil && (subscriptionStore.isLoading || subscriptionStore.products.isEmpty) {
                    ProgressView()
                        .padding(24)
                } else if let product = subscriptionStore.proMonthlyProduct {
                    VStack(spacing: 12) {
                        Text(subscriptionStore.subscriptionDisplayPrice ?? subscriptionStore.recurringPriceDescription(for: product))
                            .font(.headline)

                        Button {
                            if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                            activeTask?.cancel()
                            activeTask = Task { @MainActor in
                                do {
                                    didAttemptPurchase = true
                                    subscriptionStore.setErrorMessage(nil)
                                    _ = try await subscriptionStore.purchase(product)
                                    guard !Task.isCancelled else { return }
                                    // Don't auto-dismiss here; `isSubscribed` can briefly flip due to async entitlement refresh.
                                } catch {
                                    guard !Task.isCancelled else { return }
                                    subscriptionStore.setErrorMessage(error.localizedDescription)
                                }
                            }
                        } label: {
                            Text(purchaseButtonTitle)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppTheme.accent)
                                .foregroundStyle(.white)
                                .cornerRadius(AppTheme.smallCornerRadius)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(subscriptionStore.isLoading)

                        if let purchaseFooterText {
                            Text(purchaseFooterText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let errorMessage = subscriptionStore.errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(20)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(AppTheme.cardCornerRadius)
                    .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 8) {
                        Text("Subscription unavailable")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        if let msg = subscriptionStore.errorMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(AppTheme.cardBackground)
                    .cornerRadius(AppTheme.cardCornerRadius)
                    .padding(.horizontal, 24)
                }

                Button("Restore Purchases") {
                    if settingsStore.settings.hapticFeedback { HapticManager.lightTap() }
                    activeTask?.cancel()
                    activeTask = Task { @MainActor in
                        didAttemptPurchase = true
                        subscriptionStore.setErrorMessage(nil)
                        await subscriptionStore.restorePurchases()
                        guard !Task.isCancelled else { return }
                        // Dismiss is handled below once subscription is confirmed active.
                    }
                }
                .font(.subheadline)
                .foregroundStyle(AppTheme.accent)
                .disabled(subscriptionStore.isLoading)

                VStack(spacing: 8) {
                    Link("Privacy Policy", destination: AppURLs.privacyPolicy)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    Link("Terms of Use (EULA)", destination: AppURLs.termsOfUse)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            }
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: subscriptionStore.isSubscribed) { _, newValue in
                // Only auto-dismiss after the user actually tapped purchase/restore in this view.
                if didAttemptPurchase, newValue {
                    dismiss()
                }
            }
            .task {
                if subscriptionStore.products.isEmpty {
                    await subscriptionStore.loadProducts()
                }
            }
            .onDisappear {
                activeTask?.cancel()
            }
        }
    }

    private func paywallFeature(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

private struct SubscriptionPaywallView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionPaywallView()
            .environmentObject(SubscriptionStore.shared)
            .environmentObject(SettingsStore())
    }
}
