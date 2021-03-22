//
//  SupporterView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 15/03/2021.
//

import SwiftUI
import StoreKit

struct SupporterView: View {
    @EnvironmentObject var sgs: SurroundService
    
    var body: some View {
        ScrollView {
            VStack {
                Group {
                    if sgs.supporterProductId != nil {
                        Text("Thank you for being a Supporter!").italic()
                        Divider()
                    }
                    
                    Text("Become a Supporter to support the ongoing development of this app and gain access to some additional features.")
                        .leadingAlignedInScrollView()
                    Spacer().frame(height: 10)
                    Image("SurroundNotification")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .cornerRadius(20)
                        .padding(.horizontal, 40)
                        .frame(maxWidth: 250)
                        .shadow(radius: 2)
                }
                Spacer().frame(height: 10)
                if sgs.supporterProducts.count > 0 {
                    Text("All Supporter tiers includes:")
                        .leadingAlignedInScrollView()
                    Text("• Push notifications for correspondence games (optional)")
                        .leadingAlignedInScrollView()
                    Text("• Support for Surround's ongoing development")
                        .leadingAlignedInScrollView()
                    Divider()
                    ForEach(sgs.supporterProducts, id: \.productIdentifier) { product -> AnyView in
                        let formatter = NumberFormatter()
                        formatter.numberStyle = .currency
                        formatter.locale = product.priceLocale
                        if let price = formatter.string(from: product.price) {
                            return AnyView(Button(action: {
                                if product.productIdentifier != sgs.supporterProductId { sgs.subscribe(to: product)
                                }
                            }) {
                                VStack {
                                    HStack {
                                        Text("Supporter Tier \(String(product.productIdentifier.last!)): \(price) monthly").bold()
                                        Spacer()
                                        if sgs.processingProductIds.contains(product.productIdentifier) {
                                            ProgressView()
                                        } else if product.productIdentifier == sgs.supporterProductId {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                    Divider()
                                }
                            })
                        } else {
                            return AnyView(EmptyView())
                        }
                    }
                    if sgs.supporterProductId != nil {
                        Spacer().frame(height: 10)
                        Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                            Text("Cancel support")
                                .font(.subheadline)
                                .bold()
                                .foregroundColor(.orange)
                        }
                        Divider()
                    }
                    Group {
                        Spacer().frame(height: 15)
                        Text("If you choose to purchase a Surround App Supporter subscription, payment will be charged to your Apple ID account at the confirmation of purchase. The subscription automatically renews unless it is canceled at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period. You can manage and cancel your subscriptions by going to your account settings on the App Store after purchase.")
                            .font(.caption)
                            .leadingAlignedInScrollView()
                        Spacer().frame(height: 8)
                        Text("All purchases are final. I cannot issue refunds for purchases charged to your Apple ID.")
                            .font(.caption)
                            .leadingAlignedInScrollView()
                    }
                } else if sgs.fetchingProducts {
                    ProgressView()
                } else {
                    Text("Error: Cannot load Supporter information at the moment.")
                        .foregroundColor(.orange)
                        .leadingAlignedInScrollView()
                }
            }
            .padding()
            .frame(maxWidth: 600)
        }
        .navigationTitle("Become a Supporter")
        .onAppear {
            if sgs.supporterProducts.count == 0 {
                sgs.fetchProducts()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if sgs.processingTransaction {
                    ProgressView()
                } else {
                    Button(action: { sgs.restorePurchases() }) {
                        Text("Restore")
                    }
                }
            }
        }
    }
}

struct SupporterView_Previews: PreviewProvider {
    static var previews: some View {
        SurroundService.shared.initializeProductsForPreview()
//        userDefaults[.supporterProductId] = nil
        userDefaults[.supporterProductId] = SurroundService.shared.supporterProducts[0].productIdentifier
        return Group {
            NavigationView {
                SupporterView()
            }
            .colorScheme(.dark)
            NavigationView {
                SupporterView()
            }
        }
        .environmentObject(SurroundService.shared)
    }
}
