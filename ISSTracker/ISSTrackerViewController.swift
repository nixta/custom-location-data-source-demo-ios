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
// https://goodstuffnononsense.com/hand-drawn-icons/space-icons

import UIKit
import ArcGIS

class ISSTrackerViewController: UIViewController {
    
    @IBOutlet weak var mapView: AGSMapView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the Map.
        mapView.map = AGSMap(basemap: AGSBasemap.oceans())
        
        
        // We don't allow panning. Zoom and Rotate is OK, but we want to stay centered on the ISS.
        mapView.interactionOptions.isPanEnabled = false
        
        
        // Hide the magnifier, usually displayed if you tap and hold on the map view.
        mapView.interactionOptions.allowMagnifierToPan = false
        
        
        // Use our custom ISS Tracking Location Data Source.
        mapView.locationDisplay.dataSource = ISSLocationDataSource()
        
        
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
    }
    
    
    func configureLocationDisplay() {
        // Use AutoPan to follow the ISS.
        mapView.locationDisplay.autoPanMode = .recenter
        // The initial scale to follow the ISS at.
        mapView.locationDisplay.initialZoomScale = 10e6
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
}
