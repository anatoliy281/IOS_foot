import MetalKit


extension Renderer {
    
    public func makeReductionComputeState() -> MTLComputePipelineState? {
        let function: MTLFunction! = library.makeFunction(name: "addition_gistro") // Grab our gpu function
        guard let res = try? device.makeComputePipelineState(function: function) else {
            fatalError()
        }
        return res
    }

    public func makeConvertionComputeState() -> MTLComputePipelineState? {

        let function = library.makeFunction(name: "convert_gistro")
        do {
            return try device.makeComputePipelineState(function: function!)
        } catch {
            fatalError()
        }
    }
}



extension Renderer {
    public func makeUnprojectionPipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "unprojectVertex") else {
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.isRasterizationEnabled = false
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    public func makeGridPipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "gridVertex"),
              let fragmentFunction = library.makeFunction(name: "gridFragment") else { return nil }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat

        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    public func makeHeelMarkerAreaPipelineState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "heelMarkerAreaVertex"),
              let fragmentFunction = library.makeFunction(name: "heelMarkerAreaFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        descriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(heelAreaMesh.vertexDescriptor)
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    public func makeCameraImageState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "cameraImageVertex"),
              let fragmentFunction = library.makeFunction(name: "cameraImageFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
//        descriptor.colorAttachments[0].isBlendingEnabled = true
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    public func makePointCloudState() -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: "particleVertex"),
              let fragmentFunction = library.makeFunction(name: "particleFragment") else { return nil }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat

        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
}

