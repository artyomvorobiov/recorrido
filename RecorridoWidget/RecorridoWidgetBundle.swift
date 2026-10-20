import SwiftUI
import WidgetKit

@main
struct RecorridoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TripWidget()
        TripLiveActivity()
    }
}
