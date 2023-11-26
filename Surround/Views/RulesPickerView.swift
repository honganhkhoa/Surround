//
//  RulesPickerView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 06/02/2021.
//

import SwiftUI

struct RulesPickerView: View {
    @Binding var rulesSet: OGSRule
    @Binding var komi: Double
    @State var standardKomi = true
    var isRanked = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(OGSRule.allCases, id: \.self) { rule in
                    Button(action: { withAnimation { rulesSet = rule }}) {
                        HStack {
                            Text(rule.fullName).bold()
                            Spacer()
                            if rulesSet == rule {
                                Image(systemName: "checkmark")
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    if rulesSet == rule {
                        VStack(spacing: 0) {
                            Toggle(isOn: $standardKomi.animation()) {
                                if standardKomi {
                                    Text("Standard komi: **\(komi, specifier: "%.1f")**")
                                        .font(.subheadline)
                                } else {
                                    Text("Standard komi")
                                        .font(.subheadline)
                                }
                            }
                            .disabled(isRanked)
                            if !standardKomi {
                                Spacer().frame(height: 10)
                                Stepper(value: $komi, in: -36.5...36.5, step: 0.5) {
                                    Text("Custom komi: **\(komi, specifier: "%.1f")**")
                                        .font(.subheadline)
                                }
                            }
                            Spacer().frame(height: 5)
                            if isRanked {
                                (Text("**Custom** komi is not available in **ranked** games."))
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    Divider()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarTitle("Advanced rules settings")
        .onChange(of: standardKomi) { value in
            if value {
                withAnimation {
                    komi = rulesSet.defaultKomi
                }
            }
        }
    }
}

struct RulesPickerView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            RulesPickerView(rulesSet: .constant(.japanese), komi: .constant(OGSRule.japanese.defaultKomi))
        }
    }
}
