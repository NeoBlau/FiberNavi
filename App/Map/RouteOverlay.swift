import UIKit
import MapLibre

/// Что рисовать поверх стиля: маршруты, следующий манёвр, стрелку игрока.
struct MapOverlayState: Equatable {
    var routes: [Route] = []
    var selectedIndex = 0
    var nextManeuver: CLLocationCoordinate2D?
    /// Позиция игрока во время ведения (привязанная к маршруту). nil — системная точка MapLibre.
    var puck: CLLocationCoordinate2D?
    var puckCourse: Double = 0
    var followZoom: Double = 16

    static func == (a: Self, b: Self) -> Bool {
        a.routes == b.routes && a.selectedIndex == b.selectedIndex
            && a.nextManeuver?.latitude == b.nextManeuver?.latitude && a.nextManeuver?.longitude == b.nextManeuver?.longitude
            && a.puck?.latitude == b.puck?.latitude && a.puck?.longitude == b.puck?.longitude
            && a.puckCourse == b.puckCourse && a.followZoom == b.followZoom
    }
}

/// Оформление маршрута из токенов темы.
struct RouteStyle: Equatable {
    var color: UIColor
    var casing: UIColor
    var glow: UIColor?
    var width: Double
    var dash: [Double]?
    var alternate: UIColor = UIColor(white: 0.55, alpha: 0.8)
    var accent: UIColor

    init(tokens: ThemeTokens) {
        color = tokens.palette.route
        casing = tokens.palette.routeCasing
        glow = tokens.palette.routeGlow
        width = Double(tokens.routeWidth)
        dash = tokens.routeDash
        accent = UIColor(tokens.palette.accent)
    }
}

/// Слои маршрута и стрелки. Пересоздаются после каждой загрузки стиля (смена темы).
enum RouteLayers {
    static let routeSource = "fn-routes"
    static let pointSource = "fn-points"
    static let puckImage = "fn.puck"

    static func install(in style: MLNStyle, routeStyle: RouteStyle) {
        let routes = MLNShapeSource(identifier: routeSource, shape: nil, options: nil)
        let points = MLNShapeSource(identifier: pointSource, shape: nil, options: nil)
        style.addSource(routes)
        style.addSource(points)

        let below = style.layer(withIdentifier: "road-name-minor")
        func insert(_ layer: MLNStyleLayer) {
            if let below { style.insertLayer(layer, below: below) } else { style.addLayer(layer) }
        }
        let selected = NSPredicate(format: "selected == YES")
        let alternate = NSPredicate(format: "selected == NO")

        let alt = MLNLineStyleLayer(identifier: "fn-route-alt", source: routes)
        alt.predicate = alternate
        alt.lineColor = NSExpression(forConstantValue: routeStyle.alternate)
        alt.lineWidth = NSExpression(forConstantValue: routeStyle.width * 0.8)
        alt.lineCap = NSExpression(forConstantValue: "round")
        alt.lineJoin = NSExpression(forConstantValue: "round")
        insert(alt)

        if let glow = routeStyle.glow {
            let layer = MLNLineStyleLayer(identifier: "fn-route-glow", source: routes)
            layer.predicate = selected
            layer.lineColor = NSExpression(forConstantValue: glow)
            layer.lineWidth = NSExpression(forConstantValue: routeStyle.width * 3)
            layer.lineBlur = NSExpression(forConstantValue: routeStyle.width * 1.5)
            layer.lineCap = NSExpression(forConstantValue: "round")
            layer.lineJoin = NSExpression(forConstantValue: "round")
            insert(layer)
        }

        let casing = MLNLineStyleLayer(identifier: "fn-route-casing", source: routes)
        casing.predicate = selected
        casing.lineColor = NSExpression(forConstantValue: routeStyle.casing)
        casing.lineWidth = NSExpression(forConstantValue: routeStyle.width + 4)
        casing.lineCap = NSExpression(forConstantValue: "round")
        casing.lineJoin = NSExpression(forConstantValue: "round")
        insert(casing)

        let line = MLNLineStyleLayer(identifier: "fn-route", source: routes)
        line.predicate = selected
        line.lineColor = NSExpression(forConstantValue: routeStyle.color)
        line.lineWidth = NSExpression(forConstantValue: routeStyle.width)
        line.lineJoin = NSExpression(forConstantValue: "round")
        if let dash = routeStyle.dash {
            line.lineDashPattern = NSExpression(forConstantValue: dash)
            line.lineCap = NSExpression(forConstantValue: "butt")
        } else {
            line.lineCap = NSExpression(forConstantValue: "round")
        }
        insert(line)

        let next = MLNCircleStyleLayer(identifier: "fn-next", source: points)
        next.predicate = NSPredicate(format: "kind == 'next'")
        next.circleRadius = NSExpression(forConstantValue: 7)
        next.circleColor = NSExpression(forConstantValue: routeStyle.accent)
        next.circleStrokeColor = NSExpression(forConstantValue: UIColor.white)
        next.circleStrokeWidth = NSExpression(forConstantValue: 2)
        style.addLayer(next)

        let puck = MLNSymbolStyleLayer(identifier: "fn-puck", source: points)
        puck.predicate = NSPredicate(format: "kind == 'puck'")
        puck.iconImageName = NSExpression(forConstantValue: puckImage)
        puck.iconRotation = NSExpression(forKeyPath: "course")
        puck.iconRotationAlignment = NSExpression(forConstantValue: "map")
        puck.iconAllowsOverlap = NSExpression(forConstantValue: true)
        puck.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        style.addLayer(puck)
    }

    static func update(in style: MLNStyle, state: MapOverlayState) {
        if let source = style.source(withIdentifier: routeSource) as? MLNShapeSource {
            var features: [MLNPolylineFeature] = []
            // Альтернативы первыми, выбранный — последним, чтобы был сверху.
            let order = state.routes.indices.filter { $0 != state.selectedIndex }
                + (state.routes.indices.contains(state.selectedIndex) ? [state.selectedIndex] : [])
            for i in order {
                let coords = state.routes[i].coordinates
                guard coords.count >= 2 else { continue }
                let feature = coords.withUnsafeBufferPointer {
                    MLNPolylineFeature(coordinates: $0.baseAddress!, count: UInt($0.count))
                }
                feature.attributes = ["selected": i == state.selectedIndex]
                features.append(feature)
            }
            source.shape = MLNShapeCollectionFeature(shapes: features)
        }
        if let source = style.source(withIdentifier: pointSource) as? MLNShapeSource {
            var points: [MLNPointFeature] = []
            if let next = state.nextManeuver {
                let f = MLNPointFeature()
                f.coordinate = next
                f.attributes = ["kind": "next"]
                points.append(f)
            }
            if let puck = state.puck {
                let f = MLNPointFeature()
                f.coordinate = puck
                f.attributes = ["kind": "puck", "course": state.puckCourse]
                points.append(f)
            }
            source.shape = MLNShapeCollectionFeature(shapes: points)
        }
    }
}

extension StubArt {
    /// Стрелка игрока: треугольник с обводкой.
    static func playerArrow(color: UIColor) -> UIImage {
        let size = CGSize(width: 44, height: 44)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 22, y: 4))
            path.addLine(to: CGPoint(x: 38, y: 38))
            path.addLine(to: CGPoint(x: 22, y: 30))
            path.addLine(to: CGPoint(x: 6, y: 38))
            path.close()
            color.setFill()
            path.fill()
            UIColor.black.withAlphaComponent(0.8).setStroke()
            path.lineWidth = 2.5
            path.stroke()
        }
    }
}
