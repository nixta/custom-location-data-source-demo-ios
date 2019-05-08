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

import Foundation
import ArcGIS

extension ISSLocation {
    func agsLocation(consideringPrevious previous: AGSLocation?) -> AGSLocation {
        // Set the altitude in meters (guesstimated from https://www.heavens-above.com/IssHeight.aspx).
        let positionWithZ = AGSGeometryEngine.geometry(bySettingZ: 407000, in: position) as! AGSPoint
        
        // Default velocity and course, unless we can calculate it.
        var velocity: Double = 7666, course: Double = 0
        
        // Get the velocity and heading if we can. If not, return just the location with a guess at the velocity.
        if let previousLocation = previous, let previousPosition = previousLocation.position,
            let posDiff = AGSGeometryEngine.geodeticDistanceBetweenPoint1(positionWithZ, point2: previousPosition,
                                                                          distanceUnit: .meters(),
                                                                          azimuthUnit: .degrees(),
                                                                          curveType: .geodesic) {
            
            // We were able to get enough info to calculate the velocity and heading…
            let timeDiff = timestamp.timeIntervalSince(previousLocation.timestamp)
            velocity = posDiff.distance/timeDiff
            course = posDiff.azimuth2
        }
        
        // If this is the first location, we will set AGSLocation.lastKnown to true.
        // This causes the AGSLocationDisplay to use the `acquiringSymbol` to display the current location.
        let isFirstLocation = previous == nil
        
        // We couldn't calculate the velocity and heading, so just hard-code the velocity and return.
        return AGSLocation(position: positionWithZ, timestamp: timestamp,
                           horizontalAccuracy: 0, verticalAccuracy: 0,
                           velocity: velocity, course: course, lastKnown: isFirstLocation)
    }
}

