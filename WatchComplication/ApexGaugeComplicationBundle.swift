import SwiftUI
import WidgetKit

@main
struct ApexGaugeComplicationBundle: WidgetBundle {
    var body: some Widget {
        ApexGaugeRectangularComplication()
        ApexGaugeCircularComplication()
    }
}
