//
//  ViewController.swift
//  Exposition
//
//  Created by Andrew Thompson on 5/5/18.
//  Copyright © 2018 Andrew Thompson. All rights reserved.
//

import Cocoa
import MetalKit

extension NSEvent {
    func locationIn(mtkView: MTKView) -> CGPoint {
        return mtkView.convertToBacking(mtkView.convert(locationInWindow, from: nil))
    }
}

class ViewController: NSViewController, MTKViewDelegate, NSGestureRecognizerDelegate {
    
    var threadgroupSize: ThreadgroupSizes!
    var library: MTLLibrary!
    var commandQueue: MTLCommandQueue!
    var shader: MTLFunction!
    var pipeline: MTLComputePipelineState!
    var buffer: MTLBuffer!
    
    var cursorPosition: CGPoint = .zero
    var isMouseDown: Bool = false
    var origin: CGPoint = .zero
    
    let minimumZoom = CGSize(width: 0.2, height: 0.2)
    
    var zoom: CGSize = CGSize(width: 3, height: 3) {
        didSet {
            zoom.width = max(minimumZoom.width, zoom.width)
            zoom.height = max(minimumZoom.height, zoom.height)
        }
    }

    @IBOutlet weak var mtkView: MTKView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        mtkView.autoResizeDrawable = true
        mtkView.framebufferOnly = false
        mtkView.delegate = self
        mtkView.preferredFramesPerSecond = 30
        
        guard let device = MTLCopyAllDevices().sorted(by: {
            $0.recommendedMaxWorkingSetSize > $1.recommendedMaxWorkingSetSize
        }).first else {
            fatalError("no graphics card!")
        }
        mtkView.device = device
        
        commandQueue = device.makeCommandQueue()
        library = device.makeDefaultLibrary()
        
        shader = library.makeFunction(name: "newtonShader");
        pipeline = try! device.makeComputePipelineState(function: shader)
        buffer = device.makeBuffer(length: 6 * MemoryLayout<Float32>.size, options: [.cpuCacheModeWriteCombined])
        
        threadgroupSize = pipeline.threadgroupSizesForDrawableSize(mtkView.drawableSize)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        cursorPosition = event.locationIn(mtkView: mtkView)
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        cursorPosition = event.locationIn(mtkView: mtkView)
    }
    
    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        if !event.modifierFlags.contains(.option) {
            cursorPosition = event.locationIn(mtkView: mtkView)
        }
    }

    func draw(in view: MTKView) {
        
        if threadgroupSize.hasZeroDimension {
            return
        }
        
        autoreleasepool {
            guard let drawable = mtkView.currentDrawable else {
                return
            }
            
            guard let buffer = commandQueue.makeCommandBuffer(),
                let encoder = buffer.makeComputeCommandEncoder()
            else {
                return
            }
            
            encoder.setTexture(drawable.texture, index: 0)
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(self.buffer, offset: 0, index: 0)
            
            let buf = self.buffer.contents().bindMemory(to: Float32.self, capacity: 6)
            buf[0] = Float32(self.cursorPosition.x)
            buf[1] = Float32(self.cursorPosition.y)
            buf[2] = Float32(self.origin.x)
            buf[3] = Float32(self.origin.y)
            buf[4] = Float32(self.zoom.width)
            buf[5] = Float32(self.zoom.height)
            
            encoder.dispatchThreadgroups(threadgroupSize.threadgroupsPerGrid, threadsPerThreadgroup: threadgroupSize.threadsPerThreadgroup)
            encoder.endEncoding()
            
            buffer.present(drawable)
            buffer.commit()
            buffer.waitUntilCompleted()
        }
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let scale = CGSize(width: size.width / view.drawableSize.width, height: size.height / view.drawableSize.height)
        cursorPosition.x *= scale.width
        cursorPosition.y *= scale.height
        origin.x *= scale.width
        origin.y *= scale.height
        threadgroupSize = pipeline.threadgroupSizesForDrawableSize(size)
    }

    override func scrollWheel(with event: NSEvent) {
        origin = CGPoint(x: origin.x + event.scrollingDeltaX,
                         y: origin.y + event.scrollingDeltaY)
    }
    
    override func magnify(with event: NSEvent) {
        zoom.width *= 1 - event.magnification
        zoom.height *= 1 - event.magnification
    }
    
    override func smartMagnify(with event: NSEvent) {
        zoom.width *= 1.5
        zoom.height *= 1.5
    }
    
    @objc @IBAction func reset(_ sender: Any) {
        zoom = CGSize(width: 3,
                      height: 3)
        origin = .zero
        cursorPosition = .zero
    }
}
