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

private let errorCountForFailure = 5

/// A custom AGSLocationDataSource that uses the public ISS Location API to return
/// realtime ISS locations at 5 second intervals.
class ISSLocationDataSource: AGSLocationDataSource {

    // MARK: Properties used for getting and tracking ISS locations.
    private let issLocationAPIURL = URL(string: "http://api.open-notify.org/iss-now.json")!
    private var pollingTimer: Timer?
    private var errors: [Error] = []
    
    private var previousLocation: AGSLocation?
    
    // MARK: - FROM AGSLocationDisplay: start AGSLocationDataSource.
    override func doStart() {
        // Clear any error tracking. `errorCountForFailure` errors in a row will cause API requests to stop being sent.
        errors.removeAll()

        // MARK: TO AGSLocationDisplay: data source started OK.
        didStartOrFailWithError(nil)

        // Start the locations feed
        requestInitialLocation()
    }
    
    // MARK: FROM AGSLocationDisplay: stop AGSLocationDataSource.
    override func doStop() {
        stopRetrievingISSLocationsFromAPI()
        
        didStop()
    }

    
    // MARK: -
    func requestInitialLocation() {
        let initialLocationsGroup = DispatchGroup()
        
        // Get an initial location.
        initialLocationsGroup.enter()
        getNextLocation { [weak self] initialISSLocation in
            // MARK: TO AGSLocationDisplay: initial location available.
            self?.didUpdate(initialISSLocation)
            
            // Get another location in 1.5 seconds to quickly set the heading.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self?.getNextLocation { newISSLocation in
                    // MARK: TO AGSLocationDisplay: second location available.
                    self?.didUpdate(newISSLocation)
                    initialLocationsGroup.leave()
                }
            }
        }
        
        initialLocationsGroup.notify(timeout: .now() + 10, queue: .main) { [weak self] _ in
            // Once the first two locations have returned, start asking for more.
            // This will also start asking for locations if nothing came back for 10 seconds.
            self?.startRequestingLocationUpdates()
        }
    }
    
    func startRequestingLocationUpdates() {
        // Get ISS positions every 5 seconds (as recommended on the
        // API documentation pages):
        // http://open-notify.org/Open-Notify-API/ISS-Location-Now/
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) {
            [weak self] _ in
            
            // Request the next ISS location from the API and build an AGSLocation.
            self?.getNextLocation { newISSLocation in
                
                // MARK: TO AGSLocationDisplay: new location available.
                self?.didUpdate(newISSLocation)
            }
        }
    }
    
    func stopRetrievingISSLocationsFromAPI() {
        // Stop asking for ISS location.
        pollingTimer?.invalidate()
        pollingTimer = nil
        
        // Cancel any open requests.
        locationRequestsQueue.cancelAllOperations()
    }

    
    //MARK: - ISS Location API
    enum ISSAPIError : Error {
        case noData
    }
    
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
    func getNextLocation(completion: @escaping (AGSLocation) -> Void) {
        let locationRequest = AGSRequestOperation(url: issLocationAPIURL)
        
        locationRequest.registerListener(self) { [weak self] (data, error) in
            
            guard let self = self else { return }
            
            /// 1. Do some sanity checking of the response.
            
            // Five errors in a row will trigger the data source to stop.
            guard error == nil else {
                self.handleError(error: error!)
                return
            }

            // Get the JSON.
            guard let data = data as? Data else {
                self.handleError(error: ISSAPIError.noData)
                return
            }
            
            // Decode the JSON into an ISSLocation
            switch Result(catching: { try JSONDecoder().decode(ISSLocation.self, from: data) }) {

            case .success(let issLocationFromAPI):

                /// 2. Now turn the ISSLocation into an AGSLocation to be used by an AGSLocationDisplay.
                let location = issLocationFromAPI.agsLocation(consideringPrevious: self.previousLocation)
                
                completion(location)
                
                // Remember this as the previous location so that we can calculate velocity and heading
                // when we get the next location back.
                self.previousLocation = location
                
                // Reset error counting.
                self.errors.removeAll()

            case .failure(let error):

                // Use the specific JSON Decoding error
                self.handleError(error: error)

            }
        }
        
        // Send the JSON request to get the ISS position.
        locationRequestsQueue.addOperation(locationRequest)
    }
    
    func handleError(error: Error) {
        print("Error \(errors.count + 1) of \(errorCountForFailure): \(error.localizedDescription)")
        if errors.count >= errorCountForFailure-1 {
            print("\(errorCountForFailure) errors received. Stopping ISS location data source.")
            stopRetrievingISSLocationsFromAPI()
            didStartOrFailWithError(error)
        } else {
            errors.append(error)
        }
    }
}
