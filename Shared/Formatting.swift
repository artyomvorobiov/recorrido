import Foundation

/// Short human-friendly numbers in the user's language and units.
enum Format {
    static func distance(_ meters: Double) -> String {
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .providedUnit
        formatter.unitStyle = .medium
        if Locale.current.measurementSystem == .us {
            let miles = meters / 1609.344
            if miles < 0.1 {
                formatter.numberFormatter.maximumFractionDigits = 0
                return formatter.string(from: Measurement(value: (meters * 3.28084 / 10).rounded() * 10, unit: UnitLength.feet))
            }
            formatter.numberFormatter.maximumFractionDigits = miles < 10 ? 1 : 0
            return formatter.string(from: Measurement(value: miles, unit: UnitLength.miles))
        }
        if meters < 1000 {
            formatter.numberFormatter.maximumFractionDigits = 0
            let step = meters < 100 ? 5.0 : 10.0
            return formatter.string(from: Measurement(value: (meters / step).rounded() * step, unit: UnitLength.meters))
        }
        formatter.numberFormatter.maximumFractionDigits = meters < 10_000 ? 1 : 0
        return formatter.string(from: Measurement(value: meters / 1000, unit: UnitLength.kilometers))
    }

    static func duration(minutes: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        let rounded: Double
        if minutes >= 60 {
            formatter.allowedUnits = [.hour, .minute]
            rounded = (minutes / 5).rounded() * 5
        } else {
            formatter.allowedUnits = [.minute]
            rounded = max(1, minutes.rounded())
        }
        return formatter.string(from: rounded * 60) ?? "\(Int(rounded))"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func day(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}
