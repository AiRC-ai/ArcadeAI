import Foundation

struct TempestVectorViewportConfig: Equatable {
    static let envCenterX = "TEMPEST_SWIFT_AVG_CENTER_X"
    static let envCenterY = "TEMPEST_SWIFT_AVG_CENTER_Y"
    static let envViewportWidth = "TEMPEST_SWIFT_AVG_VIEWPORT_WIDTH"
    static let envViewportHeight = "TEMPEST_SWIFT_AVG_VIEWPORT_HEIGHT"

    static let defaultCenterX = 290.5
    static let defaultCenterY = 285.5
    static let defaultViewportWidth = 581.0
    static let defaultViewportHeight = 571.0

    let centerX: Double
    let centerY: Double
    let width: Double
    let height: Double

    var minX: Double { centerX - (width * 0.5) }
    var minY: Double { centerY - (height * 0.5) }
    var maxX: Double { centerX + (width * 0.5) }
    var maxY: Double { centerY + (height * 0.5) }

    static func swiftAVG(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TempestVectorViewportConfig {
        TempestVectorViewportConfig(
            centerX: envDouble(
                envCenterX,
                defaultValue: defaultCenterX,
                environment: environment
            ),
            centerY: envDouble(
                envCenterY,
                defaultValue: defaultCenterY,
                environment: environment
            ),
            width: envPositiveDouble(
                envViewportWidth,
                defaultValue: defaultViewportWidth,
                environment: environment
            ),
            height: envPositiveDouble(
                envViewportHeight,
                defaultValue: defaultViewportHeight,
                environment: environment
            )
        )
    }

    private static func envDouble(
        _ key: String,
        defaultValue: Double,
        environment: [String: String]
    ) -> Double {
        guard
            let raw = environment[key],
            let value = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
            value.isFinite
        else {
            return defaultValue
        }
        return value
    }

    private static func envPositiveDouble(
        _ key: String,
        defaultValue: Double,
        environment: [String: String]
    ) -> Double {
        let value = envDouble(
            key,
            defaultValue: defaultValue,
            environment: environment
        )
        return value > 1.0 ? value : defaultValue
    }
}
