//
// Copyright © 2019 Esri.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

// ISS Icon provided under Creative Commons 4.0 by https://goodstuffnononsense.com
// http://www.iconarchive.com/show/free-space-icons-by-goodstuff-no-nonsense/international-space-station-icon.html

import UIKit
import ArcGIS

class ISSTrackerViewController: UIViewController {

    // MARK: -
    // MARK: Main Map View
    @IBOutlet weak var mapView: AGSMapView! {
        didSet {
            // Add some overlays for displaying the ISS track and an estimate of what's visible.
            mapView.graphicsOverlays.add(issTrackOverlay)
            mapView.graphicsOverlays.add(issVisibilityOverlay)

            configureLatLonGrid()
        }
    }
    
    let issTrackOverlay: AGSGraphicsOverlay = {
        let overlay = AGSGraphicsOverlay()
        overlay.renderer = AGSSimpleRenderer(symbol: AGSCompositeSymbol(symbols: [
            AGSSimpleLineSymbol(style: .solid, color: UIColor.red.withAlphaComponent(0.3), width: 10),
            AGSSimpleLineSymbol(style: .solid, color: UIColor.orange.withAlphaComponent(0.5), width: 6)
            ]))
        overlay.graphics.add(AGSGraphic(geometry: nil, symbol: nil, attributes: nil))
        return overlay
    }()
    
    let issVisibilityOverlay: AGSGraphicsOverlay = {
        let overlay = AGSGraphicsOverlay()
        let symbol = AGSSimpleFillSymbol(style: .solid, color: UIColor.red.withAlphaComponent(0.08),
                                         outline: AGSSimpleLineSymbol(style: .solid,
                                                                      color: UIColor.red.withAlphaComponent(0.5),
                                                                      width: 1))
        overlay.renderer = AGSSimpleRenderer(symbol: symbol)
        overlay.graphics.add(AGSGraphic(geometry: nil, symbol: nil, attributes: nil))
        overlay.maxScale = 15e6
        
        return overlay
    }()


    //MARK: Overview Map View
    @IBOutlet weak var overviewMapView: AGSMapView! {
        didSet { // Set up the global context overview map view.
            overviewMapView.map = AGSMap(basemap: AGSBasemap.imagery())
            
            overviewMapView.interactionOptions.isEnabled = false
            overviewMapView.isAttributionTextVisible = false
            overviewMapView.graphicsOverlays.add(overviewContextOverlay)
            overviewMapView.graphicsOverlays.add(overviewTrackOverlay)
            overviewMapView.graphicsOverlays.add(overviewLocationOverlay)

            overviewMapView.layer.cornerRadius = 10
            overviewMapView.layer.borderColor = UIColor.blue.cgColor
            overviewMapView.layer.borderWidth = 2
        }
    }
    
    let overviewContextOverlay: AGSGraphicsOverlay = {
        let overlay = AGSGraphicsOverlay()
        overlay.renderer = AGSSimpleRenderer(symbol: AGSSimpleFillSymbol(style: .solid, color: .white, outline: nil))
        overlay.opacity = 0.4
        overlay.graphics.add(AGSGraphic(geometry: nil, symbol: nil, attributes: nil))
        return overlay
    }()
    
    let overviewTrackOverlay: AGSGraphicsOverlay = {
        let overlay = AGSGraphicsOverlay()
        overlay.renderer = AGSSimpleRenderer(symbol: AGSSimpleLineSymbol(style: .dot, color: .orange, width: 2))
        overlay.graphics.add(AGSGraphic(geometry: nil, symbol: nil, attributes: nil))
        return overlay
    }()
    
    let overviewLocationOverlay : AGSGraphicsOverlay = {
        let overlay = AGSGraphicsOverlay()
        let symbol = AGSSimpleMarkerSymbol(style: .circle, color: UIColor.red.withAlphaComponent(0.25), size: 8)
        symbol.outline = AGSSimpleLineSymbol(style: .solid, color: .white, width: 1)
        overlay.renderer = AGSSimpleRenderer(symbol: symbol)
        overlay.graphics.add(AGSGraphic(geometry: nil, symbol: nil, attributes: nil))
        return overlay
    }()
    
    
    // MARK: Miscellaneous
    let trackBuilder = AGSPolylineBuilder(spatialReference: .wgs84())
    var trackAntimeridianTraversalCount = 0
    
    var lastLocation: AGSLocation?

    
    // MARK: -
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the Map.
        mapView.map = AGSMap(basemap: AGSBasemap.oceans())
        
        
        // We don't allow panning. Zoom and Rotate is OK, but we want to stay centered on the ISS.
        mapView.interactionOptions.isPanEnabled = false
        

        // Use our custom ISS Tracking Location Data Source.
        mapView.locationDisplay.dataSource = ISSLocationDataSource()
        
        
        // Update the map display whenever a new ISS location is emitted.
        mapView.locationDisplay.locationChangedHandler = { [weak self] newLocation in
            guard let self = self, let newPosition = newLocation.position else { return }
            
            var leaveGap = false
            if let lastTimestamp = self.lastLocation?.timestamp, newLocation.timestamp.timeIntervalSince(lastTimestamp) > 10 {
                // We hadn't had any updates for a little while, let's start a new polyline part for the track.
                // Could be because the app was backgrounded, or because the API stopped responding.
                leaveGap = true
            }
            
            // Update the map display to reflect the latest ISS position.
            self.updateISSTrack(with: newPosition, leaveGap: leaveGap)
            self.updateISSEstimatedViewshed(for: newPosition)
            self.updateISSOverviewMap(for: newPosition)
            
            self.lastLocation = newLocation
        }
                

        // Start the AGSMapView's AGSLocationDisplay. This will start the
        // custom data source and begin receiving location updates from it.
        mapView.locationDisplay.start { (error) in
            guard error == nil else {
                print("Error starting up location tracking: \(error!.localizedDescription)")
                return
            }
        }

        
        // Set some configuration on the Location Display.
        configureLocationDisplay()


        // Set up some custom behavior for when the map display area changes.
        configureMapViewViewpointChangedHandler()
    }
    
    func updateISSTrack(with newPosition: AGSPoint, leaveGap shouldStartNewPart: Bool) {
        // ISS locations are normalized between -180 and +180 longitude. To build a continuous line that
        // doesn't jump from, for example, 179.9 to -179.9 (and draw a horizontal line across the globe)
        // we'll "denormalize" it.
        //
        // Assumptions:
        // ISS will travel in a +ve longitudinal direction. This will never change.
        // The track builder AND newPosition will be working in WGS84.
        if trackBuilder.parts.count > 0 {
            let lastPart = trackBuilder.parts.part(at: trackBuilder.parts.count-1)
            let newLon = newPosition.x + Double(360 * trackAntimeridianTraversalCount)
            if let lastPtWGS84 = lastPart.endPoint, newLon < lastPtWGS84.x {
                // We just passed the antimeridian!
                trackAntimeridianTraversalCount += 1
            }
        }
        
        // Denormalize the line to ensure we keep orbiting…
        let denormalizedNewPosition = AGSPointMakeWGS84(newPosition.y, newPosition.x + Double(360 * trackAntimeridianTraversalCount))

        if shouldStartNewPart {
            trackBuilder.addPart(with: [denormalizedNewPosition])
        } else {
            trackBuilder.add(denormalizedNewPosition)
        }
        
        // Now reflect the updated track on the map view(s).
        updateISSTrackDisplay(with: trackBuilder.toGeometry())
    }


    // MARK: - Update on-map information as the ISS moves…
    func updateISSTrackDisplay(with trackGeometry: AGSPolyline) {
        if let trackGraphic = issTrackOverlay.graphics.firstObject as? AGSGraphic {
            trackGraphic.geometry = trackGeometry
        }
        if let trackGraphic = overviewTrackOverlay.graphics.firstObject as? AGSGraphic {
            trackGraphic.geometry = trackGeometry
        }
    }
    
    func updateISSOverviewMap(for newPosition: AGSPoint) {
        if let issGraphic = overviewLocationOverlay.graphics.firstObject as? AGSGraphic {
            issGraphic.geometry = newPosition
        }
    }
    
    func updateISSEstimatedViewshed(for issPosition: AGSPoint) {
        if let visibilityGraphic = issVisibilityOverlay.graphics.firstObject as? AGSGraphic {
            let geometry = AGSGeometryEngine.geodeticBufferGeometry(issPosition,
                                                                    distance: 2200, distanceUnit: .kilometers(),
                                                                    maxDeviation: Double.nan, curveType: .geodesic)
            visibilityGraphic.geometry = AGSGeometryEngine.normalizeCentralMeridian(of: geometry!)
        }
    }


    func configureLatLonGrid() {
        // Configure the Lat/Lon grid that's displayed over the map for context when zoomed in.
        let grid = AGSLatitudeLongitudeGrid()
        mapView.grid = grid
        
        grid.labelFormat = AGSLatitudeLongitudeGridLabelFormat.degreesMinutesSeconds
        grid.setLineSymbol(AGSSimpleLineSymbol(style: .solid, color: UIColor.black.withAlphaComponent(0.3), width: 1), forLevel: 0)
    }
    
    func configureLocationDisplay() {
        
        // Use AutoPan to follow the ISS.
        mapView.locationDisplay.autoPanMode = .recenter
        
        // The initial scale to follow the ISS at.
        mapView.locationDisplay.initialZoomScale = 53e6
        
        // Constantly follow the ISS. When it moves, the map moves. If this was greater than 0,
        // the ISS could make its way towards the edge of the map before the map panned to follow
        // it.
        mapView.locationDisplay.wanderExtentFactor = 0

        // Configure the AGSLocationDisplay to show the ISS icon instead of the default blue dot.
        if let issImage = UIImage(named: "iss") {
            mapView.locationDisplay.courseSymbol = AGSPictureMarkerSymbol(image: issImage)
            if let acquiringImage = issImage.noir {
                let acquiringSymbol = AGSPictureMarkerSymbol(image: acquiringImage)
                acquiringSymbol.opacity = 0.25
                mapView.locationDisplay.acquiringSymbol = acquiringSymbol
            }
        }

        reenableAutoPanAfterNavigation()
    }
    
    var observers: [NSKeyValueObservation] = []
    
    func reenableAutoPanAfterNavigation() {
        // As the user zooms in and out, we want to ensure autoPan is still on. Normally,
        // interacting with the map will turn off auto-pan, but for this demo we don't
        // want that behavior.
        observers.append(mapView.observe(\.isNavigating) { (changedMapView, _) in
            guard changedMapView.isNavigating == false else { return }
            
            changedMapView.locationDisplay.autoPanMode = .recenter
        })
    }

    // MARK: - Hook into map view interactions
    func configureMapViewViewpointChangedHandler() {
        mapView.viewpointChangedHandler = { [mapView = mapView!, context = overviewContextOverlay] in
            // We want to turn the Grid off if we're too far out.
            mapView.grid?.isVisible = mapView.mapScale < 88e6

            guard let geom = mapView.visibleArea else { return }
            
            // When the main map view's visible area changes, reflect this in the overview
            if let contextGraphic = context.graphics.firstObject as? AGSGraphic {
                contextGraphic.geometry = geom
            }
        }

    }
}
