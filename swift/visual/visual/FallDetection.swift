//
//  FallDetection.swift
//  visual
//
//  Created by Chi-Ping Su on 2021/5/24.
//

import CoreMotion
import AVFoundation

final class FallDetection: ObservableObject{
    var location: Location = Location()
    let motion = CMMotionManager()
    var x = 999.0
    var y = 999.0
    var z = 999.0
    var isFallDetected = false
    var count = 0
    var timer: Timer?
    var timer2: Timer?
    var fallState = false
    var reportState = false
    var fallPlayer = AVAudioPlayer()
    var callPlayer = AVAudioPlayer()
    
    func startAccelerometers() {
        // Make sure the accelerometer hardware is available.
        if self.motion.isAccelerometerAvailable {
            self.motion.accelerometerUpdateInterval = 1.0 / 60.0  // 60 Hz
            self.motion.startAccelerometerUpdates()
            
            self.timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
                if self.isFallDetected {
                    if !self.fallState {
//                        self.motion.stopAccelerometerUpdates()
                        self.fallPlayer.play()
                        self.startCountDown()
                    }
                    self.fallState = true
                } else {
                    if let data = self.motion.accelerometerData {
                        self.x = data.acceleration.x
                        self.y = data.acceleration.y
                        self.z = data.acceleration.z
//                        print("x:" + String(self.x) + "y:" + String(self.y) + "z:" + String(self.z))
                        if  (abs(self.x) + abs(self.y) + abs(self.z)) >= 3.0
                        {
                            self.isFallDetected = true
                        }
                    }
                }
            }
        }
    }
    
    func startCountDown() {
        self.timer2 = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.count += 1
            if self.count >= 15{
                self.reportState = true
                self.location.request()
                self.callPlayer.play()
                self.timer2?.invalidate()
            }
        }
    }
    
    func reset() {
        if fallPlayer.isPlaying {
            fallPlayer.pause()
            fallPlayer.currentTime = 0
        }
        self.count = 0
        self.fallState = false
        self.reportState = false
        self.timer2?.invalidate()
        self.x = 0
        self.y = 0
        self.z = 0
        self.isFallDetected = false
    }
    
    init?() {
        startAccelerometers()
        
        let fallUrl = Bundle.main.url(forResource: "fall", withExtension: "mp3", subdirectory: "TTS")!
        let callUrl = Bundle.main.url(forResource: "call", withExtension: "mp3", subdirectory: "TTS")!
        do {
            fallPlayer  = try AVAudioPlayer(contentsOf: fallUrl)
            callPlayer  = try AVAudioPlayer(contentsOf: callUrl)
        } catch {
            print(error)
        }
        fallPlayer.prepareToPlay()
        callPlayer.prepareToPlay()
    }
}
