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

//MARK: - Custom AGSLocationDataSource

/// A custom AGSLocationDataSource that uses the public ISS Location API to return
/// realtime ISS locations at 5 second intervals.
class ISSLocationDataSource: AGSLocationDataSource {
    
    private let issLocationAPIURL = URL(string: "http://api.open-notify.org/iss-now.json")!
    private var pollingTimer: Timer?
    
    private var previousLocation: AGSLocation?
    
    // MARK: - FROM AGSLocationDisplay: start AGSLocationDataSource.
    override func doStart() {
        
        // MARK: TO AGSLocationDisplay: data source started OK.
        didStartOrFailWithError(nil)

        startRequestingLocationUpdates()
    }
    
    // MARK: FROM AGSLocationDisplay: stop AGSLocationDataSource.
    override func doStop() {
        stopRetrievingISSLocationsFromAPI()
        
        didStop()
    }
    
    // MARK: -
    func startRequestingLocationUpdates() {
        // Get ISS positions every 5 seconds (as recommended on the
        // API documentation pages):
        // http://open-notify.org/Open-Notify-API/ISS-Location-Now/
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) {
            [weak self] _ in
            
            // Request the next ISS location from the API and build an AGSLocation.
            self?.requestNextLocation { newISSLocation in
                
                // MARK: TO AGSLocationDisplay: new location available.
                self?.didUpdate(newISSLocation)
                
            }
            
        }
        
        // Get a first location immediately.
        pollingTimer?.fire()
    }
    
    func stopRetrievingISSLocationsFromAPI() {
        // Stop asking for ISS location.
        pollingTimer?.invalidate()
        pollingTimer = nil
        
        // Cancel any open requests.
        locationRequestsQueue.cancelAllOperations()
    }
    
    //MARK: - ISS Location API
    
    //MARK: Make a request for the current location
    var locationRequestsQueue: AGSOperationQueue = {
        let q = AGSOperationQueue()
        q.qualityOfService = .userInitiated
        q.maxConcurrentOperationCount = 1
        return q
    }()
    
    /// Make a request to the ISS Tracking API and return an AGSLocation.
    ///
    /// - Parameter completion: The completion closure is called when the AGSLocation has been obtained.
    func requestNextLocation(completion: @escaping (AGSLocation) -> Void) {
        
        let locationRequest = AGSRequestOperation(url: issLocationAPIURL)
        
        locationRequest.registerListener(self) { [weak self] (data, error) in
            
            guard let self = self else { return }
            
            guard error == nil else {
                print("Error from location API: \(error!.localizedDescription)")
                return
            }
            
            /// 1. Do some sanity checking of the response.
            guard let data = data as? Data,
                let issLocationFromAPI = try? JSONDecoder().decode(ISSLocation.self, from: data) else {
                    print("Unable to parse JSON!")
                    return
            }
            
            /// 2. Now turn the response into an AGSLocation to be used by an AGSLocationDisplay.
            let location = issLocationFromAPI.agsLocation(consideringPrevious: self.previousLocation)
            
            completion(location)
            
            // Remember this as the previous location so that we can calculate velocity and heading
            // when we get the next location back.
            self.previousLocation = location
        }
        
        // Send the JSON request to get the ISS position.
        locationRequestsQueue.addOperation(locationRequest)
    }
    
}
