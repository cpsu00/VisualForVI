//
//  Location.swift
//  visual
//
//  Created by Chi-Ping Su on 2021/6/11.
//

import CoreLocation

class Location: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var lastSeenLocation: CLLocation?
    @Published var reqLocStatus = false
    
    var isLoading = false
    
    var connection: Connection = Connection()
    
    var userSettings = UserSettings()
    private let locationManager: CLLocationManager
    
    var coordinate: CLLocationCoordinate2D? {
        self.lastSeenLocation?.coordinate
    }
    
    override init() {
        locationManager = CLLocationManager()
        authorizationStatus = locationManager.authorizationStatus
        
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
    
    func request(){
        self.isLoading = true
        self.reqLocStatus = false
        connection.conStatus = false
        connection.responseStatus = ""
        locationManager.requestLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastSeenLocation = locations.first
        reqLocStatus = true
        connection.SendMsg(user_id: userSettings.user_id, user_name: userSettings.user_name, lat: String(self.coordinate?.latitude ?? 0.0), long: String(self.coordinate?.longitude ?? 0.0))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isLoading = false
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to get users location.")
    }
}
