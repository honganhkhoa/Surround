import SwiftUI
import UIKit

/// The spinner of a search that is starting or waiting: Home's searching
/// card, New Game's waiting banner and Quick Match's status.
///
/// UI tests show it stopped. A spinning one redraws the screen about 20 times
/// a second, and the recording Xcode makes of each UI test takes a frame for
/// every redraw. The compatibility fixtures keep searches waiting, and in slow
/// iPadOS 18 CI runs, tests on screens with two of these spinners answered
/// queries an order of magnitude more slowly than the tests around them,
/// enough for one to run out of its time allowance.
struct SearchSpinner: View {
    var tint: Color?

    var body: some View {
        if SurroundUITestContract.isEnabled {
            StoppedActivityIndicator(color: tint.map { UIColor($0) })
        } else if let tint {
            ProgressView()
                .tint(tint)
        } else {
            ProgressView()
        }
    }
}

private struct StoppedActivityIndicator: UIViewRepresentable {
    let color: UIColor?

    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.hidesWhenStopped = false
        // Taps reach the control around it, as they do past ProgressView.
        indicator.isUserInteractionEnabled = false
        return indicator
    }

    func updateUIView(_ indicator: UIActivityIndicatorView, context: Context) {
        if let color {
            indicator.color = color
        }
    }
}
