//
//  Pipeline.swift
//  Exposition
//
//  Created by Andrew Thompson on 14/5/18.
//  Copyright © 2018 Andrew Thompson. All rights reserved.
//

import MetalKit

extension String {
    func expand(macro: String, value: String) -> String {
        var output = ""
        enumerateLines { (line, stop) in
            if !line.trimmingCharacters(in: CharacterSet.whitespaces).starts(with: "#") {
                output += line.replacingOccurrences(of: macro, with: value) + "\n"
            } else {
                output += line + "\n"
            }
        }
        return output
    }
}

class Shader {
    var function: MTLFunction
    var pipeline: MTLComputePipelineState
    var buffer: MTLBuffer
    var image: NSImage {
        get {
            if _image == nil {
                _image = makeImage(parameters: [CGPoint(x: 256, y: 256), CGPoint(x: 256, y: 256)])
            }
            return _image!
        }
    }
    
    private var _image: NSImage? = nil
    private var threadgroupSize: ThreadgroupSizes? = nil
    private var size: CGSize? = nil
    
    init(function: MTLFunction, pipeline: MTLComputePipelineState, buffer: MTLBuffer) {
        self.function = function
        self.pipeline = pipeline
        self.buffer = buffer
    }
    
    func screenToComplex(point: CGPoint) -> Complex {
        // map point from car_size into com_size
        let carSize = CGSize(width: 1024, height: 1024)
        let comSize = CGSize(width: 4, height: 4)
        let comOri = CGPoint(x: -2, y: -2)
        
        return Complex(Double((point.x / carSize.width) * comSize.width + comOri.x),
                       Double((point.y / carSize.height) * comSize.height + comOri.y))
    }
    
    func initaliseBuffer(parameters: [CGPoint], zoom: CGFloat, origin: CGPoint) {
        let count = 2 * parameters.count + 2 + 2
        let buf = buffer.contents().bindMemory(to: Float32.self, capacity: count)
        
        let allParameters: [CGPoint] = [origin, CGPoint(x: zoom, y: zoom)] + parameters
        
        for (i, p) in allParameters.enumerated() {
            buf[i * 2] = Float32(p.x)
            buf[i * 2 + 1] = Float32(p.y)
        }
    }
    
    func makeImage(size: CGSize = CGSize(width: 512, height: 512),
                   parameters: [CGPoint],
                   zoom: CGFloat = CGFloat(1),
                   origin: CGPoint = CGPoint(x: 0, y: 0)) -> NSImage? {
        
        guard let metal = AppDelegate.shared.metal else {
            fatalError()
        }
        
        initaliseBuffer(parameters: parameters,
                        zoom: zoom,
                        origin: origin
        )
        
        let layer = CAMetalLayer()
        layer.allowsNextDrawableTimeout = false
        layer.displaySyncEnabled = false
        layer.presentsWithTransaction = false
        layer.frame.size = size
        layer.device = metal.device
        layer.framebufferOnly = false
        
        let colorspace = CGColorSpaceCreateDeviceRGB()
        layer.colorspace = colorspace

        return autoreleasepool {
            let drawable = layer.nextDrawable()
            if !draw(commandQueue: metal.commandQueue, buffer: buffer, size: layer.drawableSize, currentDrawable: drawable) {
                return nil
            }
            
            let context = CIContext(mtlDevice: metal.device, options: [CIContextOption.workingColorSpace : colorspace])
            
            guard let texture = drawable?.texture else {
                return nil
            }
            
            guard let cImg = CIImage(mtlTexture: texture, options: nil) else {
                return nil
            }
            
            guard let cgImg = context.createCGImage(cImg, from: cImg.extent) else {
                return nil
            }
            
            return NSImage(cgImage: cgImg, size: size)
        }
    }
    
    
    static func makeShaders(metal: MetalVars) -> [Shader] {
        let device = metal.device
        let url = Bundle.main.url(forResource: "Shaders", withExtension: "metal")!
        let source = try! String(contentsOf: url)

        func constants(_ val: Bool) -> MTLFunctionConstantValues {
            var value: Bool = val
            let values = MTLFunctionConstantValues()
            values.setConstantValue(&value, type: .bool, withName: "use_escape_iteration")
            return values
        }
        
        func function(equation: String, usingEscapeIteration: Bool)  throws -> MTLFunction {
            let preprocessedSource = source.expand(macro: "iterator", value: equation)
            let lib = try device.makeLibrary(source: preprocessedSource, options: nil)
            let f = try lib.makeFunction(name: "newtonShader", constantValues: constants(usingEscapeIteration))
            f.label  = "\(f.name), using escape iteration \(usingEscapeIteration)"
            return f
        }
        
        func shader(iterator: String, usingEscapeIteration: Bool) -> Shader? {
            guard let buffer = device.makeBuffer(length: 8 * MemoryLayout<Float32>.size, options: [.cpuCacheModeWriteCombined]) else {
                return nil
            }
            
            do {
                let d = try function(equation: iterator,
                                     usingEscapeIteration: usingEscapeIteration)
                let pipeline = try device.makeComputePipelineState(function: d)
                return Shader(function: d, pipeline: pipeline, buffer: buffer)
            } catch {
                print(error)
                fatalError()
            }
        }
        
        return [
            shader(iterator: "z - c * ((((z * z * z) - 1)/(3 * (z * z))))", usingEscapeIteration: true), // cubic zeros
            shader(iterator: "z - c * (z.pow(3) - 1)/(3 * z.pow(2)) + p", usingEscapeIteration: true), // cubic zeros
            shader(iterator: "z - c * (1/((z*z*z) - 1))/((-3*(z*z))/((z*z*z) - 1))", usingEscapeIteration: true), // log of z power z
            shader(iterator: "z - c * sin(z*z*z - 1)/(cos(z*z*z - 1)*3*(z*z*z))", usingEscapeIteration: true), // log of z power z
            shader(iterator: "z - c * (0.5 * z + 1/z)", usingEscapeIteration: false), // square root zeros
            shader(iterator: "z - c * cos(z)/(-sin(z))", usingEscapeIteration: true), // cosine zeros
            shader(iterator: "z*z + c", usingEscapeIteration: true), // julia set
            shader(iterator: "z*z + Z", usingEscapeIteration: true), // mandelbrot set
            shader(iterator: "z - c * ((((z * z * z * z * z) - 1)/(5 * (z * z * z * z))))", usingEscapeIteration: true),
            shader(iterator: "z - c * (z.pow(3) + z + 1)/(3*z.pow(2) + 1)", usingEscapeIteration: true),
            shader(iterator: "z - c * log(z^z) / (log(z) + 1)", usingEscapeIteration: true), // log of z power z
            shader(iterator: "z - c * log(z^(2*z)) / (log(2*z) + 1)", usingEscapeIteration: true), // log of z power z
            shader(iterator: "z - c * log(z*z*z) * 3 * z", usingEscapeIteration: true), // log of z power z
            shader(iterator: "z - c * log(z*z*z*z) * 4 * z", usingEscapeIteration: true), // log of z power z
            shader(iterator: "z - c * (((z*z*z) - 1)/e((3*(z*z))/((z*z*z) - 1)))", usingEscapeIteration: true), // log of z power z
            ].compactMap { $0 }
    }
    
    func checkThreadgroupSize(for drawableSize: CGSize) -> ThreadgroupSizes {
        if size != drawableSize || threadgroupSize == nil {
            threadgroupSize = pipeline.threadgroupSizesForDrawableSize(drawableSize)
            size = drawableSize
        }
        return threadgroupSize!
    }
    
    func draw(commandQueue: MTLCommandQueue, buffer buff: MTLBuffer, size drawableSize: CGSize, currentDrawable: @autoclosure () -> CAMetalDrawable?) -> Bool {
        
        if checkThreadgroupSize(for: drawableSize).hasZeroDimension {
            return false
        }

        return autoreleasepool {
            guard let drawable = currentDrawable() else {
                print(#file, #function, "currentDrawable nil!")
                return false
            }
            
            guard let buffer = commandQueue.makeCommandBuffer(),
                let encoder = buffer.makeComputeCommandEncoder()
                else {
                    print(#file, #function, "buffer or encoder nil!")
                    return false
            }
            
            encoder.setTexture(drawable.texture, index: 0)
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(buff, offset: 0, index: 0)
            
            encoder.dispatchThreadgroups(threadgroupSize!.threadgroupsPerGrid,
                                         threadsPerThreadgroup: threadgroupSize!.threadsPerThreadgroup)
            encoder.endEncoding()
            
            buffer.commit()
            buffer.waitUntilCompleted()
            return true
        }
    }
    
    func draw(in view: MTKView) {
        
        if checkThreadgroupSize(for: view.drawableSize).hasZeroDimension {
            return
        }
        
        autoreleasepool {
            guard let drawable = view.currentDrawable else {
                print("currentDrawable nil!")
                return
            }
            
            guard let commandQueue = AppDelegate.shared.metal?.commandQueue else {
                print("commandQueue nil, and we're drawing?")
                return
            }
            
            guard let buffer = commandQueue.makeCommandBuffer(),
                let encoder = buffer.makeComputeCommandEncoder()
                else {
                    print("buffer or encoder nil!")
                    return
            }
            
            encoder.setTexture(drawable.texture, index: 0)
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(self.buffer, offset: 0, index: 0)
            
            encoder.dispatchThreadgroups(threadgroupSize!.threadgroupsPerGrid,
                                         threadsPerThreadgroup: threadgroupSize!.threadsPerThreadgroup)
            encoder.endEncoding()
            
            buffer.present(drawable)
            buffer.commit()
            buffer.waitUntilCompleted()
        }
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToOptionalCIContextOptionDictionary(_ input: [String: Any]?) -> [CIContextOption: Any]? {
	guard let input = input else { return nil }
	return Dictionary(uniqueKeysWithValues: input.map { key, value in (CIContextOption(rawValue: key), value)})
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromCIContextOption(_ input: CIContextOption) -> String {
	return input.rawValue
}
