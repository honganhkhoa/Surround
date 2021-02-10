//
//  TimeSystemPickerView.swift
//  Surround
//
//  Created by Anh Khoa Hong on 04/02/2021.
//

import SwiftUI

private let timeSteps = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12,
    15, 20, 25, 30, 35, 40, 45, 50, 55, 60,
    70, 80, 90,
    105, 120,
    150, 180, 210, 240, 270, 300,
    360, 420, 480, 540, 600, 720,
    900, 1200, 1500, 1800, 2100, 2400, 2700, 3000, 3300, 3600,
    4200, 4800, 5400, 6000, 6600, 7200,
    8100, 9000, 9900, 10800,
    12600, 14400,
    16200, 18000, 19800, 21600,
    25200, 28800, 36000, 43200,
    57600, 72000,
    86400,
    86400 + 43200,
    86400 * 2,
    86400 * 3,
    86400 * 4,
    86400 * 5,
    86400 * 6,
    86400 * 7,
    86400 * 8,
    86400 * 9,
    86400 * 10,
    86400 * 11,
    86400 * 12,
    86400 * 13,
    86400 * 14,
    86400 * 21,
    86400 * 28
]

private let stepIndex: [Int: Int] = {
    var result = [Int: Int]()
    for index in timeSteps.indices {
        result[timeSteps[index]] = index
    }
    return result
}()

struct TimeStepper<Label>: View where Label: View {
    var value: Binding<Int?>
    var range: ClosedRange<Int>
    var canBeZero = false
    var label: () -> Label
    
    var body: some View {
        if let wrappedValue = value.wrappedValue {
            Stepper(
                value: Binding(
                    get: { wrappedValue },
                    set: {
                        if wrappedValue == 0 && $0 > wrappedValue {
                            value.wrappedValue = range.lowerBound
                        } else if let index = stepIndex[wrappedValue] {
                            if $0 < wrappedValue {
                                if wrappedValue == range.lowerBound && canBeZero {
                                    value.wrappedValue = 0
                                } else if index > 0 {
                                    value.wrappedValue = timeSteps[index - 1]
                                }
                            } else if $0 > wrappedValue && index < timeSteps.count - 1 {
                                value.wrappedValue = timeSteps[index + 1]
                            }
                        }
                    }
                ),
                in: canBeZero ? 0...range.upperBound : range,
                label: label
            )
        } else {
            EmptyView()
        }
    }
}

struct TimeControlAdjustmentSteppers: View {
    @Binding var timeControl: TimeControl
    var timeControlSpeed: TimeControlSpeed
    
    typealias TimeRanges = [TimeControlSpeed: [KeyPath<TimeControl.TimeControlCodingData, Int?>: ClosedRange<Int>]]
    
    let byoYomiRanges: TimeRanges = [
        .blitz: [
            \.mainTime: 1...300,
            \.periodTime: 1...10
        ],
        .live: [
            \.mainTime: 30...3600 * 4,
            \.periodTime: 10...3600
        ],
        .correspondence: [
            \.mainTime: 86400...86400 * 28,
            \.periodTime: 86400...86400 * 28
        ]
    ]
    
    let fischerRanges: TimeRanges = [
        .blitz: [
            \.initialTime: 5...300,
            \.timeIncrement: 1...10,
            \.maxTime: 5...300
        ],
        .live: [
            \.initialTime: 30...3600,
            \.timeIncrement: 10...1800,
            \.maxTime: 30...3600
        ],
        .correspondence: [
            \.initialTime: 86400...86400 * 28,
            \.timeIncrement: 14400...86400 * 7,
            \.maxTime: 86400...86400 * 28
        ]
    ]
    
    let canadianRanges: TimeRanges = [
        .blitz: [
            \.mainTime: 1...300,
            \.periodTime: 5...30
        ],
        .live: [
            \.mainTime: 30...3600 * 4,
            \.periodTime: 20...3600
        ],
        .correspondence: [
            \.mainTime: 86400...86400 * 28,
            \.periodTime: 86400...86400 * 28
        ]
    ]
    
    let simpleRanges: TimeRanges = [
        .blitz: [\.perMove: 3...9],
        .live: [\.perMove: 10...3600],
        .correspondence: [\.perMove: 86400...86400 * 28]
    ]
    
    let absoluteRanges: TimeRanges = [
        .blitz: [\.totalTime: 30...300],
        .live: [\.totalTime: 600...14400],
        .correspondence: [\.totalTime: 86400 * 7...86400 * 28]
    ]
    
    var timeRanges: TimeRanges {
        switch timeControl.system {
        case .ByoYomi:
            return byoYomiRanges
        case .Fischer:
            return fischerRanges
        case .Canadian:
            return canadianRanges
        case .Simple:
            return simpleRanges
        case .Absolute:
            return absoluteRanges
        case .None:
            return [:]
        }
    }
    
    func timeStepper(keyPath: WritableKeyPath<TimeControl.TimeControlCodingData, Int?>, canBeZero: Bool = false, label: String) -> some View {
        TimeStepper(
            value: Binding(
                get: { timeControl.codingData[keyPath: keyPath] },
                set: { timeControl.codingData[keyPath: keyPath] = $0 }
            ),
            range: timeRanges[timeControlSpeed]![keyPath]!,
            canBeZero: canBeZero
        ) {
            Text("\(label): ").bold() +
                Text(durationString(seconds: timeControl.codingData[keyPath: keyPath]!, longFormat: true))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            switch timeControl.system {
            case .ByoYomi:
                timeStepper(keyPath: \.mainTime, canBeZero: true, label: "Main time")
                if let periods = timeControl.periods {
                    Stepper(value: Binding(get: { periods }, set: { timeControl.periods = $0 }), in: 1...300) {
                        Text("Periods: ").bold() + Text("\(periods)")
                    }
                }
                timeStepper(keyPath: \.periodTime, label: "Time per period")
            case .Fischer:
                timeStepper(keyPath: \.initialTime, label: "Initial time")
                timeStepper(keyPath: \.timeIncrement, label: "Time increment")
                timeStepper(keyPath: \.maxTime, label: "Max time")
            case .Canadian:
                timeStepper(keyPath: \.mainTime, canBeZero: true, label: "Main time")
                timeStepper(keyPath: \.periodTime, label: "Time per period")
                if let stonePerPeriod = timeControl.stonesPerPeriod {
                    Stepper(
                        value: Binding(
                            get: { stonePerPeriod },
                            set: { timeControl.stonesPerPeriod = $0 }
                        ),
                        in: 1...50
                    ) {
                        Text("Stone per period: ").bold() + Text("\(stonePerPeriod)")
                    }
                }
            case .Simple:
                timeStepper(keyPath: \.perMove, label: "Time per move")
            case .Absolute:
                timeStepper(keyPath: \.totalTime, label: "Total time")
            case .None:
                EmptyView()
            }
        }
    }
}

struct TimeSystemPickerView: View {
    var blitzTimeControl: Binding<TimeControl>
    var liveTimeControl: Binding<TimeControl>
    var correspondenceTimeControl: Binding<TimeControl>
    @Binding var timeControlSpeed: TimeControlSpeed
    @Binding var isBlitz: Bool
    @Binding var pauseOnWeekend: Bool

    var finalTimeControlSpeed: TimeControlSpeed {
        if timeControlSpeed == .correspondence {
            return .correspondence
        } else {
            if isBlitz {
                return .blitz
            } else {
                return timeControlSpeed
            }
        }
    }

    var finalTimeControl: Binding<TimeControl> {
        switch finalTimeControlSpeed {
        case .blitz:
            return blitzTimeControl
        case .live:
            return liveTimeControl
        case .correspondence:
            return correspondenceTimeControl
        }
    }

    var body: some View {
        let defaultOptions = finalTimeControlSpeed.defaultTimeOptions
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Picker(selection: $timeControlSpeed.animation(), label: Text("Game speed")) {
                    Text("Live").tag(TimeControlSpeed.live)
                    Text("Correspondence").tag(TimeControlSpeed.correspondence)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                if timeControlSpeed == .live {
                    Spacer().frame(height: 10)
                    Toggle(isOn: $isBlitz) {
                        Text("Blitz").font(.subheadline)
                    }.padding(.horizontal)
                } else if timeControlSpeed == .correspondence {
                    Spacer().frame(height: 10)
                    Toggle(isOn: $pauseOnWeekend) {
                        Text("Pause on weekend").font(.subheadline)
                    }.padding(.horizontal)
                }
                Spacer().frame(height: 20)
                Divider()
                ForEach(defaultOptions.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 0) {
                        Button(action: {
                            withAnimation {
                                finalTimeControl.wrappedValue = defaultOptions[index].timeControlObject
                            }
                        }) {
                            HStack {
                                Text(defaultOptions[index].name).font(.headline)
                                    .padding()
                                Spacer()
                                if defaultOptions[index].name == finalTimeControl.wrappedValue.systemName {
                                    Image(systemName: "checkmark")
                                        .padding()
                                }
                            }
                        }
                        if defaultOptions[index].name == finalTimeControl.wrappedValue.systemName {
                            VStack(alignment: .leading) {
                                TimeControlAdjustmentSteppers(
                                    timeControl: finalTimeControl,
                                    timeControlSpeed: finalTimeControlSpeed
                                )
                                finalTimeControl.wrappedValue.system.descriptionText
                            }
                            .font(.subheadline)
                            .padding(.horizontal)
                            .padding(.bottom)
                        }
                        Divider()
                    }
                }
            }.padding(.vertical)
        }
        .navigationBarTitle("Advanced time settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TimeSystemPickerView_Previews: PreviewProvider {
    static var previews: some View {
        let blitzTimeControl = TimeControlSpeed.blitz.defaultTimeOptions[0].timeControlObject
        let liveTimeControl = TimeControlSpeed.live.defaultTimeOptions[0].timeControlObject
        let correspondenceTimeControl = TimeControlSpeed.correspondence.defaultTimeOptions[0].timeControlObject

        return Group {
            NavigationView {
                TimeSystemPickerView(
                    blitzTimeControl: .constant(blitzTimeControl),
                    liveTimeControl: .constant(liveTimeControl),
                    correspondenceTimeControl: .constant(correspondenceTimeControl),
                    timeControlSpeed: .constant(.live),
                    isBlitz: .constant(false),
                    pauseOnWeekend: .constant(true)
                )
            }
        }
    }
}
