/*
 See LICENSE folder for this sample’s licensing information.
 
 Abstract:
 A utility class that provides processed depth information.
 */

import Foundation
import SwiftUI
import Combine
import ARKit
import Accelerate
import MetalPerformanceShaders
import AVFoundation

// Wrap the `MTLTexture` protocol to reference outputs from ARKit.
final class MetalTextureContent {
    var texture: MTLTexture?
}

// Enable `CVPixelBuffer` to output an `MTLTexture`.
extension CVPixelBuffer {
    
    func texture(withFormat pixelFormat: MTLPixelFormat, planeIndex: Int, addToCache cache: CVMetalTextureCache) -> MTLTexture? {
        
        let width = CVPixelBufferGetWidthOfPlane(self, planeIndex)
        let height = CVPixelBufferGetHeightOfPlane(self, planeIndex)
        
        var cvtexture: CVMetalTexture?
        _ = CVMetalTextureCacheCreateTextureFromImage(nil, cache, self, nil, pixelFormat, width, height, planeIndex, &cvtexture)
        let texture = CVMetalTextureGetTexture(cvtexture!)
        
        return texture
        
    }
    
}

// Collect AR data using a lower-level receiver. This class converts AR data
// to a Metal texture, optionally upscaling depth data using a guided filter,
// and implements `ARDataReceiver` to respond to `onNewARData` events.
final class ARProvider: ARDataReceiver, ObservableObject {
    // Set the destination resolution for the upscaled algorithm.
    let upscaledWidth = 960
    let upscaledHeight = 760
    
    // Set the original depth size.
    let origDepthWidth = 256
    let origDepthHeight = 192
    
    // Set the original color size.
    let origColorWidth = 1920
    let origColorHeight = 1440
    
    // Set the guided filter constants.
    let guidedFilterEpsilon: Float = 0.004
    let guidedFilterKernelDiameter = 5
    
    let arReceiver = ARReceiver()
    @Published var lastArData: ARData?
    let depthContent = MetalTextureContent()
    let confidenceContent = MetalTextureContent()
    let colorYContent = MetalTextureContent()
    let colorCbCrContent = MetalTextureContent()
    let upscaledCoef = MetalTextureContent()
    let downscaledRGB = MetalTextureContent()
    let upscaledConfidence = MetalTextureContent()
    
    var beepPlayer = AVAudioPlayer()
    var frontPlayer = AVAudioPlayer()
    var leftPlayer = AVAudioPlayer()
    var rightPlayer = AVAudioPlayer()
    var crowdPlayer = AVAudioPlayer()
    var signPlayer = AVAudioPlayer()
    var bottlePlayer = AVAudioPlayer()
    var phonePlayer = AVAudioPlayer()
    var bookPlayer = AVAudioPlayer()
    var carPlayer = AVAudioPlayer()
    
    var dFront = false
    var dLeft = false
    var dRight = false
    var dCrowd = false
    var dSign = false
    
    var minDist: Float
    var lrThresh: Float
    
    var distanceAtXYBotR: Float32
    var distanceAtXYBotM: Float32
    var distanceAtXYBotL: Float32
    
    let coefTexture: MTLTexture
    let destDepthTexture: MTLTexture
    let destConfTexture: MTLTexture
    let colorRGBTexture: MTLTexture
    let colorRGBTextureDownscaled: MTLTexture
    let colorRGBTextureDownscaledLowRes: MTLTexture
    
    // Enable or disable depth upsampling.
    public var isToUpsampleDepth: Bool = true {
        didSet {
            processLastArData()
        }
    }
    
    // Enable or disable smoothed-depth upsampling.
    public var isUseSmoothedDepthForUpsampling: Bool = true {
        didSet {
            processLastArData()
        }
    }
    var textureCache: CVMetalTextureCache?
    let metalDevice: MTLDevice?
    let guidedFilter: MPSImageGuidedFilter?
    let mpsScaleFilter: MPSImageBilinearScale?
    let commandQueue: MTLCommandQueue?
    let pipelineStateCompute: MTLComputePipelineState?
    
    var requests = [VNRequest]()
    var detectedObject = [String]()
    var objectBounds = [[Int]]()
    var obj = ["mouse","cell phone","laptop","keyboard","tvmonitor","remote","book","umbrella","handbag","backpack","cup","bottle"]
    var pNum = 0
    var objMode = false
    var convertedImage: UIImage?
    
    // Create an empty texture.
    static func createTexture(metalDevice: MTLDevice, width: Int, height: Int, usage: MTLTextureUsage, pixelFormat: MTLPixelFormat) -> MTLTexture {
        let descriptor: MTLTextureDescriptor = MTLTextureDescriptor()
        descriptor.pixelFormat = pixelFormat
        descriptor.width = width
        descriptor.height = height
        descriptor.usage = usage
        let resTexture = metalDevice.makeTexture(descriptor: descriptor)
        return resTexture!
    }
    
    // Start or resume the stream from ARKit.
    func start() {
        arReceiver.start()
    }
    
    // Pause the stream from ARKit.
    func pause() {
        arReceiver.pause()
    }
    
    // Initialize the MPS filters, metal pipeline, and Metal textures.
    init?() {
        do {
            metalDevice = MTLCreateSystemDefaultDevice()
            CVMetalTextureCacheCreate(nil, nil, metalDevice!, nil, &textureCache)
            guidedFilter = MPSImageGuidedFilter(device: metalDevice!, kernelDiameter: guidedFilterKernelDiameter)
            guidedFilter?.epsilon = guidedFilterEpsilon
            mpsScaleFilter = MPSImageBilinearScale(device: metalDevice!)
            commandQueue = metalDevice!.makeCommandQueue()
            let lib = metalDevice!.makeDefaultLibrary()
            let convertYUV2RGBFunc = lib!.makeFunction(name: "convertYCbCrToRGBA")
            pipelineStateCompute = try metalDevice!.makeComputePipelineState(function: convertYUV2RGBFunc!)
            // Initialize the working textures.
            coefTexture = ARProvider.createTexture(metalDevice: metalDevice!, width: origDepthWidth, height: origDepthHeight,
                                                   usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
            destDepthTexture = ARProvider.createTexture(metalDevice: metalDevice!, width: upscaledWidth, height: upscaledHeight,
                                                        usage: [.shaderRead, .shaderWrite], pixelFormat: .r32Float)
            destConfTexture = ARProvider.createTexture(metalDevice: metalDevice!, width: upscaledWidth, height: upscaledHeight,
                                                       usage: [.shaderRead, .shaderWrite], pixelFormat: .r8Unorm)
            colorRGBTexture = ARProvider.createTexture(metalDevice: metalDevice!, width: origColorWidth, height: origColorHeight,
                                                       usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
            colorRGBTextureDownscaled = ARProvider.createTexture(metalDevice: metalDevice!, width: upscaledWidth, height: upscaledHeight,
                                                                 usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
            colorRGBTextureDownscaledLowRes = ARProvider.createTexture(metalDevice: metalDevice!, width: origDepthWidth, height: origDepthHeight,
                                                                       usage: [.shaderRead, .shaderWrite], pixelFormat: .rgba32Float)
            upscaledCoef.texture = coefTexture
            upscaledConfidence.texture = destConfTexture
            downscaledRGB.texture = colorRGBTextureDownscaled
            
            distanceAtXYBotR = 999.0
            distanceAtXYBotM = 999.0
            distanceAtXYBotL = 999.0
            
            let beepUrl = Bundle.main.url(forResource: "beep", withExtension: "mp3", subdirectory: "TTS")!
            let frontUrl = Bundle.main.url(forResource: "前", withExtension: "mp3", subdirectory: "TTS")!
            let leftUrl = Bundle.main.url(forResource: "左", withExtension: "mp3", subdirectory: "TTS")!
            let rightUrl = Bundle.main.url(forResource: "右", withExtension: "mp3", subdirectory: "TTS")!
            let crowdUrl = Bundle.main.url(forResource: "人群", withExtension: "mp3", subdirectory: "TTS")!
            let signUrl = Bundle.main.url(forResource: "路口", withExtension: "mp3", subdirectory: "TTS")!
            let bottleUrl = Bundle.main.url(forResource: "水瓶", withExtension: "mp3", subdirectory: "TTS")!
            let phoneUrl = Bundle.main.url(forResource: "手機", withExtension: "mp3", subdirectory: "TTS")!
            let bookUrl = Bundle.main.url(forResource: "書", withExtension: "mp3", subdirectory: "TTS")!
            let carUrl = Bundle.main.url(forResource: "車", withExtension: "mp3", subdirectory: "TTS")!
            
            
            do {
                beepPlayer  = try AVAudioPlayer(contentsOf: beepUrl)
                frontPlayer = try AVAudioPlayer(contentsOf: frontUrl)
                leftPlayer  = try AVAudioPlayer(contentsOf: leftUrl)
                rightPlayer = try AVAudioPlayer(contentsOf: rightUrl)
                crowdPlayer = try AVAudioPlayer(contentsOf: crowdUrl)
                signPlayer  = try AVAudioPlayer(contentsOf: signUrl)
                bottlePlayer  = try AVAudioPlayer(contentsOf: bottleUrl)
                phonePlayer = try AVAudioPlayer(contentsOf: phoneUrl)
                bookPlayer = try AVAudioPlayer(contentsOf: bookUrl)
                carPlayer  = try AVAudioPlayer(contentsOf: carUrl)
            } catch {
                print(error)
            }
            
            beepPlayer.prepareToPlay()
            frontPlayer.prepareToPlay()
            leftPlayer.prepareToPlay()
            rightPlayer.prepareToPlay()
            crowdPlayer.prepareToPlay()
            signPlayer.prepareToPlay()
            bottlePlayer.prepareToPlay()
            phonePlayer.prepareToPlay()
            bookPlayer.prepareToPlay()
            carPlayer.prepareToPlay()
            
            minDist = UserDefaults.standard.object(forKey: "user_dist") as? Float ?? 1.5
            lrThresh = UserDefaults.standard.object(forKey: "user_lr") as? Float ?? 60.0
            
            arReceiver.delegate = self
            
            setupVision()
            
        } catch {
            print("Unexpected error: \(error).")
            return nil
        }
    }
    
    // Save a reference to the current AR data and process it.
    func onNewARData(arData: ARData) {
        lastArData = arData
        processLastArData()
    }
    
    // Copy the AR data to Metal textures and, if the user enables the UI, upscale the depth using a guided filter.
    func processLastArData() {
        colorYContent.texture = lastArData?.colorImage?.texture(withFormat: .r8Unorm, planeIndex: 0, addToCache: textureCache!)!
        colorCbCrContent.texture = lastArData?.colorImage?.texture(withFormat: .rg8Unorm, planeIndex: 1, addToCache: textureCache!)!
        if isUseSmoothedDepthForUpsampling {
//            player.prepareToPlay()
            depthContent.texture = lastArData?.depthSmoothImage?.texture(withFormat: .r32Float, planeIndex: 0, addToCache: textureCache!)!
            confidenceContent.texture = lastArData?.confidenceSmoothImage?.texture(withFormat: .r8Unorm, planeIndex: 0, addToCache: textureCache!)!
            
            if let depthDataMap = lastArData?.depthSmoothImage!{
                CVPixelBufferLockBaseAddress(depthDataMap, CVPixelBufferLockFlags(rawValue: 0))
                let depthPointer = unsafeBitCast(CVPixelBufferGetBaseAddress(depthDataMap), to: UnsafeMutablePointer<Float32>.self)
                let depthArray = Array(UnsafeBufferPointer(start: depthPointer, count: 192*256))
                
                distanceAtXYBotR = 999.0
                distanceAtXYBotL = 999.0
                distanceAtXYBotM = 999.0
                
                for x in 0...191{
                    let st = x*256+0
                    let ed = x*256+220
                    
                    if x < (192*Int(lrThresh)/2/100){
                        if depthArray[st...ed].min()! < distanceAtXYBotR{
                            distanceAtXYBotR = depthArray[st...ed].min()!
                        }
                    }
                    else if x >= (192-192*Int(lrThresh)/2/100){
                        if depthArray[st...ed].min()! < distanceAtXYBotL{
                            distanceAtXYBotL = depthArray[st...ed].min()!
                        }
                    }
                    else{
                        if depthArray[st...ed].min()! < distanceAtXYBotM{
                            distanceAtXYBotM = depthArray[st...ed].min()!
                        }
                    }
                }
            }
        } else {
            depthContent.texture = lastArData?.depthImage?.texture(withFormat: .r32Float, planeIndex: 0, addToCache: textureCache!)!
            confidenceContent.texture = lastArData?.confidenceImage?.texture(withFormat: .r8Unorm, planeIndex: 0, addToCache: textureCache!)!
        }
        if isToUpsampleDepth {
            guard let commandQueue = commandQueue else { return }
            guard let cmdBuffer = commandQueue.makeCommandBuffer() else { return }
            guard let computeEncoder = cmdBuffer.makeComputeCommandEncoder() else { return }
            // Convert YUV to RGB because the guided filter needs RGB format.
            computeEncoder.setComputePipelineState(pipelineStateCompute!)
            computeEncoder.setTexture(colorYContent.texture, index: 0)
            computeEncoder.setTexture(colorCbCrContent.texture, index: 1)
            computeEncoder.setTexture(colorRGBTexture, index: 2)
            let threadgroupSize = MTLSizeMake(pipelineStateCompute!.threadExecutionWidth,
                                              pipelineStateCompute!.maxTotalThreadsPerThreadgroup / pipelineStateCompute!.threadExecutionWidth, 1)
            let threadgroupCount = MTLSize(width: Int(ceil(Float(colorRGBTexture.width) / Float(threadgroupSize.width))),
                                           height: Int(ceil(Float(colorRGBTexture.height) / Float(threadgroupSize.height))),
                                           depth: 1)
            computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
            computeEncoder.endEncoding()
            
            // Downscale the RGB data. Pass in the target resoultion.
            mpsScaleFilter?.encode(commandBuffer: cmdBuffer, sourceTexture: colorRGBTexture,
                                   destinationTexture: colorRGBTextureDownscaled)
            // Match the input depth resolution.
            mpsScaleFilter?.encode(commandBuffer: cmdBuffer, sourceTexture: colorRGBTexture,
                                   destinationTexture: colorRGBTextureDownscaledLowRes)
            
            // Upscale the confidence data. Pass in the target resolution.
            mpsScaleFilter?.encode(commandBuffer: cmdBuffer, sourceTexture: confidenceContent.texture!,
                                   destinationTexture: destConfTexture)
            
            // Encode the guided filter.
            guidedFilter?.encodeRegression(to: cmdBuffer, sourceTexture: depthContent.texture!,
                                           guidanceTexture: colorRGBTextureDownscaledLowRes, weightsTexture: nil,
                                           destinationCoefficientsTexture: coefTexture)
            
            // Optionally, process `coefTexture` here.
            
            guidedFilter?.encodeReconstruction(to: cmdBuffer, guidanceTexture: colorRGBTextureDownscaled,
                                               coefficientsTexture: coefTexture, destinationTexture: destDepthTexture)
            cmdBuffer.commit()
            
            // Override the original depth texture with the upscaled version.
            depthContent.texture = destDepthTexture
        }
        
        convertImage()
        DispatchQueue.global(qos: .default).async {
            self.predictUsingVision(pixelBuffer: (self.lastArData?.colorImage)!)
        }
        
        minDist = UserDefaults.standard.object(forKey: "user_dist") as? Float ?? 1.5
        lrThresh = UserDefaults.standard.object(forKey: "user_lr") as? Float ?? 60.0
        
        if !frontPlayer.isPlaying && !leftPlayer.isPlaying && !rightPlayer.isPlaying{
            if distanceAtXYBotM < minDist {
                frontPlayer.play()
            }
            else if distanceAtXYBotL < minDist {
                leftPlayer.play()
            }
            else if distanceAtXYBotR < minDist {
                rightPlayer.play()
            }
        }
    }
    
    func setupVision() {
        // Setup Vision parts
        do {
            let visionModel = try VNCoreMLModel(for: YOLOv3().model)
            let objectRecognition = VNCoreMLRequest(model: visionModel, completionHandler: { (request, error) in
                DispatchQueue.main.async(execute: {
                    // perform all the UI updates on the main queue
                    if let results = request.results {
                        self.drawVisionRequestResults(results)
                    }
                })
            })
            self.requests = [objectRecognition]
        } catch let error as NSError {
            print("Model loading went wrong: \(error)")
        }
    }
    
    func drawVisionRequestResults(_ results: [Any]) {
        pNum = 0
        detectedObject = []
        objectBounds = []
        for observation in results where observation is VNRecognizedObjectObservation {
            guard let objectObservation = observation as? VNRecognizedObjectObservation else {
                continue
            }
            // Select only the label with the highest confidence.
            let topLabelObservation = objectObservation.labels[0]
            let objectBound = VNImageRectForNormalizedRect(objectObservation.boundingBox, Int((lastArData?.cameraResolution.width)!), Int((lastArData?.cameraResolution.height)!))
            let xRange = Int(1920*0.3)...Int(1920*0.7)
            let yRange = Int(1440*0.0)...Int(1440*1.0)
            
            
            if topLabelObservation.identifier == "person" && topLabelObservation.confidence>0.5{
                detectedObject.append("人")
                objectBounds.append([Int(objectBound.midY), Int(objectBound.midX)])
                pNum += 1
            }
            else if topLabelObservation.identifier == "traffic light" && topLabelObservation.confidence>0.5{
                signPlayer.play()
                detectedObject.append("路口")
                objectBounds.append([Int(objectBound.midY), Int(objectBound.midX)])
            }
            else if (topLabelObservation.identifier == "car" || topLabelObservation.identifier == "bus" || topLabelObservation.identifier == "motorbike") && topLabelObservation.confidence>0.5{
                carPlayer.play()
                detectedObject.append("車")
                objectBounds.append([Int(objectBound.midY), Int(objectBound.midX)])
            }
            else if objMode && topLabelObservation.identifier == "bottle" && topLabelObservation.confidence>0.5 && yRange.contains(Int(objectBound.midY)) && xRange.contains(Int(objectBound.midX)){
                bottlePlayer.play()
                detectedObject.append(topLabelObservation.identifier)
                objectBounds.append([Int(objectBound.midY), Int(objectBound.midX)])
            }
            else if objMode && topLabelObservation.identifier == "phone" && topLabelObservation.confidence>0.5 && yRange.contains(Int(objectBound.midY)) && xRange.contains(Int(objectBound.midX)){
                phonePlayer.play()
                detectedObject.append(topLabelObservation.identifier)
                objectBounds.append([Int(objectBound.midY), Int(objectBound.midX)])
            }
            else if objMode && topLabelObservation.identifier == "book" && topLabelObservation.confidence>0.5 && yRange.contains(Int(objectBound.midY)) && xRange.contains(Int(objectBound.midX)){
                bookPlayer.play()
                detectedObject.append(topLabelObservation.identifier)
                objectBounds.append([Int(objectBound.midY), Int(objectBound.midX)])
            }
            else if objMode && obj.contains(topLabelObservation.identifier) && topLabelObservation.confidence>0.5 && yRange.contains(Int(objectBound.midY)) && xRange.contains(Int(objectBound.midX)){
                detectedObject.append(topLabelObservation.identifier)
                objectBounds.append([Int(objectBound.midY), Int(objectBound.midX)])
            }
        }
        if pNum >= 3{
            detectedObject.append("人群")
            objectBounds.append([0,0])
            crowdPlayer.play()
        }
    }
    
    func predictUsingVision(pixelBuffer: CVPixelBuffer)
    {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform(requests)
    }
    
    func convertImage()
    {
        let ciimage : CIImage = CIImage(cvPixelBuffer: (self.lastArData?.colorImage)!)
        let context:CIContext = CIContext(options: nil)
        let cgImage:CGImage = context.createCGImage(ciimage, from: ciimage.extent)!
        convertedImage = UIImage(cgImage: cgImage, scale: 4, orientation: .right)
    }
}

