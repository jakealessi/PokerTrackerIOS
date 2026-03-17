//
//  SubscriptionPaywallView.swift
//  PokerTrackerIOS
//

import SwiftUI
import StoreKit

struct SubscriptionPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var subscriptionStore: SubscriptionStore
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
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(AppTheme.accent)
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.top, 20)

                if subscriptionStore.isLoading && subscriptionStore.proMonthlyProduct == nil {
                    ProgressView("Loading subscription…")
                        .padding()
                } else if let product = subscriptionStore.proMonthlyProduct {
                    VStack(spacing: 12) {
                        Text(subscriptionStore.subscriptionDisplayPrice ?? subscriptionStore.recurringPriceDescription(for: product))
                            .font(.headline)

                        Button {
                            activeTask?.cancel()
                            activeTask = Task {
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
                    Text("Subscription unavailable")
                        .foregroundStyle(.secondary)
                    if let msg = subscriptionStore.errorMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }

                Button("Restore Purchases") {
                    activeTask?.cancel()
                    activeTask = Task {
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
                    Link("Terms of Use (EULA)", destination: AppURLs.termsOfUse)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                Spacer()
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
}

private struct SubscriptionPaywallView_Previews: PreviewProvider {
    static var previews: some View {
        SubscriptionPaywallView()
            .environmentObject(SubscriptionStore.shared)
    }
}
