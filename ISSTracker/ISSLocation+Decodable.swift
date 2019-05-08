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

// Example JSON returned from the ISS Location API at http://api.open-notify.org/iss-now.json
//
// {
//     "timestamp": 1557499056,
//     "message": "success",
//     "iss_position": {
//         "latitude": "-47.7396",
//         "longitude": "39.7870"
//     }
// }

extension ISSLocation: Decodable {
    private enum CodingKeys: String, CodingKey {
        case position = "iss_position", timestamp
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        timestamp = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .timestamp))
        position = try container.decode(Position.self, forKey: .position).point
    }
}

internal struct Position: Decodable {
    let latitude: Double
    let longitude: Double

    private enum CodingKeys: String, CodingKey {
        case latitude, longitude
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = Double(try container.decode(String.self, forKey: .latitude))!
        longitude = Double(try container.decode(String.self, forKey: .longitude))!
    }
    
    var point: AGSPoint {
        return AGSPointMakeWGS84(latitude, longitude)
    }
}
