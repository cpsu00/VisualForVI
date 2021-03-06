//
//  ContentView.swift
//  visual
//
//  Created by Chi-Ping Su on 2021/5/24.
//

import SwiftUI
import ARKit
import UIKit
import MetalKit
import CoreMotion
import AVFoundation
import Vision

import VideoToolbox

struct ContentView: View {
    @ObservedObject var location = Location()
    @ObservedObject var userSettings = UserSettings()
    @State private var showingImagePicker = false
    
    
    var body: some View {
        switch location.authorizationStatus {
        case .restricted:
            ErrorView(errorText: "Location use is restricted.")
        case .denied:
            ErrorView(errorText: "The app does not have location permissions. Please enable them in settings.")
        default:
            SenseView()
                .environmentObject(location)
        }
        //        VStack {
        //            PreviewHolder()
        //        }.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .center)
        
    }
}

struct SenseView: View {
    @ObservedObject var arProvider: ARProvider = ARProvider()!
    let ciContext: CIContext = CIContext()
    @ObservedObject var fallDetection: FallDetection = FallDetection()!
    @EnvironmentObject var location: Location
    private var captureSession: AVCaptureSession?
    
    @State private var selectedConfidence = 0
    @State var isToUpsampleDepth = true
    @State var isShowSmoothDepth = true
    @State var isArPaused = false
    @State var closeObject: Float = 0.0
    @State var user_name: String = ""
    @State var user_id: String = ""
    @State var lat = "0.0"
    @State var long = "0.0"
    @State var showAR = false
    @State var showCam = false
    
    let userDefault = UserDefaults()
    
    var coordinate: CLLocationCoordinate2D? {
        location.lastSeenLocation?.coordinate
    }
    
    var longPress: some Gesture {
        LongPressGesture(minimumDuration: 1.0)
            .onEnded { finished in
                fallDetection.reset()
            }
    }
    
    
    var body: some View {
        NavigationView {
            VStack {
                if !fallDetection.isFallDetected {
                    VStack {
                        Spacer()
                        
                        HStack() {
                            if #available(iOS 15.0, *) {
                                Toggle("????????????", isOn: $showCam)
                                    .toggleStyle(.button)
                                    .tint(.blue)
                                    .onChange(of: showCam) { value in
                                        showAR = false
                                    }
                                Spacer()
                                Toggle("LiDAR??????", isOn: $showAR)
                                    .toggleStyle(.button)
                                    .tint(.blue)
                                    .onChange(of: showAR) { value in
                                        showCam = false
                                    }
                                Spacer()
                                Toggle(isOn: $arProvider.objMode){
                                    Text("????????????")
                                }
                                .toggleStyle(.button)
                                .tint(.blue)
                            } else {
                                Button("????????????"){
                                    showAR = false
                                    showCam.toggle()
                                }
                                Spacer()
                                Button("LiDAR??????"){
                                    showAR.toggle()
                                    showCam = false
                                }
                                Spacer()
                                Button("????????????"){
                                    arProvider.objMode.toggle()
                                }
                            }
                        }
                        .font(.system(size: 18))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 15)
                        .frame(minWidth: 360, maxWidth: 360, alignment: .center)
                        .background(Color.white)
                        .cornerRadius(5)
                        
                        Spacer()
                        
                        HStack {
                            if showCam && arProvider.convertedImage != nil{
                                Image(uiImage: arProvider.convertedImage!).frame(width: 360, height: 480)
                            }
                            else if showAR{
                                MetalTextureViewDepth(mtkView: MTKView(), content: arProvider.depthContent, confSelection: $selectedConfidence).frame(width: 360, height: 480)
                            }
                        }
                        .frame(minWidth: 360, minHeight: 480)
                        .cornerRadius(5)
                        
                        Spacer()
                        
                        VStack{
                            HStack {
                                Text(String(format: "%3.2f", arProvider.distanceAtXYBotL)+"m")
                                Spacer()
                                Text(String(format: "%3.2f", arProvider.distanceAtXYBotM)+"m")
                                Spacer()
                                Text(String(format: "%3.2f", arProvider.distanceAtXYBotR)+"m")
                            }
                            .font(.system(size: 20))
                            
                            HStack {
                                VStack{
                                    ForEach(arProvider.detectedObject, id: \.self) { obj in
                                        Text(obj.description)
                                    }
                                }
                                VStack(alignment: .leading){
                                    ForEach(arProvider.objectBounds, id: \.self) { obj in
                                        Text(obj.description)
                                    }
                                }
                            }
                            .font(.system(size: 20))
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 15)
                        .frame(minWidth: 360, maxWidth: 360, minHeight: 90, maxHeight: 90 ,alignment: .top)
                        .foregroundColor(Color.black)
                        .background(Color.white)
                        .cornerRadius(5)
                        
                        Spacer()
                    }
                }
                else{
                    VStack {
                        if (fallDetection.reportState)
                        {
                            Text("???????????????")
                                .font(.system(size: 50))
                                .foregroundColor(.black)
                                .padding()
                            Text("?????????????????????")
                                .font(.system(size: 30))
                                .foregroundColor(.black)
                        }
                        else
                        {
                            Text("???????????????")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                            Text("??????" + String(15-fallDetection.count) + "?????????????????????")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .padding()
                            Text("?????????????????????")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .background(Color.red)
                    .edgesIgnoringSafeArea(.all)
                    .gesture(longPress)
                }
            }
            .navigationBarTitle("???????????????")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    NavigationLink(
                        destination: SettingsView(),
                        label: {
                            Text("??????")
                                .font(.system(size: 24))
                        })
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var userSettings = UserSettings()
    @EnvironmentObject var location: Location
    @Environment(\.colorScheme) var colorScheme
    @State private var showAlert = false
    @State private var didError = false
    
    
    var coordinate: CLLocationCoordinate2D? {
        location.lastSeenLocation?.coordinate
    }
    
    var body: some View {
        ZStack{
            if location.isLoading{
                HStack(spacing: 20){
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: (colorScheme == .dark ? Color.black : Color.white)))
                        .scaleEffect(1.2, anchor: .center)
                    if location.connection.conStatus{
                        Text("?????????")
                    }
                    else if location.reqLocStatus{
                        Text("?????????")
                    }
                    else{
                        Text("????????????????????????")
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 15)
                .frame(width: 150,height: 60)
                .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
                .background(colorScheme == .light ? Color.black.opacity(0.3) : Color.white.opacity(0.7))
                .cornerRadius(10)
                .zIndex(1)
            }
            Form {
                Section(header: Text("????????????")) {
                    VStack(alignment: .leading){
                        Text("??????????????????")
                        HStack() {
                            Slider(value: $userSettings.user_dist, in: 0.5...2.0, step: 0.1)
                            Text(String(format: "%2.2f", userSettings.user_dist)+"??????")
                        }
                        Text("???????????????????????????????????????")
                        HStack() {
                            Slider(value: $userSettings.user_lr, in: 0.0...99.0, step: 1.0)
                            Text(String(format: "%3.0f", userSettings.user_lr)+"%")
                        }
                        HStack() {
                            Spacer()
                            Button("???????????????"){
                                userSettings.user_dist = 1.5
                                userSettings.user_lr = 60.0
                            }
                            Spacer()
                        }
                    }
                }
                Section(header: Text("??????????????????")) {
                    VStack(alignment: .leading) {
                        Text("????????????")
                        TextField("????????????", text: $userSettings.user_name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        Text("?????????Line??????")
                        TextField("Key", text: $userSettings.user_id)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    HStack() {
                        Spacer()
                        Button("??????????????????"){
                            location.request()
                        }
                        Spacer()
                    }
                }
            }
            .zIndex(0)
            .navigationBarTitle("Settings")
        }
    }
}

struct ErrorView: View {
    var errorText: String
    
    var body: some View {
        VStack {
            Image(systemName: "xmark.octagon")
                .resizable()
                .frame(width: 100, height: 100, alignment: .center)
            Text(errorText)
        }
        .padding()
        .foregroundColor(.white)
        .background(Color.red)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
        }
    }
}

struct BlueButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 0, maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
    }
}

struct SquareButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 100, height: 40)
            .font(.title)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(20)
    }
}
