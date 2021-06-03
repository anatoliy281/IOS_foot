import MetalKit


extension Renderer {
    
    public func makeComputeFootMetricState() -> MTLComputePipelineState? {
        let function: MTLFunction! = library.makeFunction(name: "computeFootMetric") // Grab our gpu function
        guard let res = try? device.makeComputePipelineState(function: function) else {
            fatalError()
        }
        return res
    }
}



extension Renderer {
    private func makeBaseUnprojectionPipelineState(shaderFuncName:String) -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: shaderFuncName) else {
            return nil
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.isRasterizationEnabled = false
        descriptor.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        descriptor.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    
    public func makeCartesianUnprojectPipelineState() -> MTLRenderPipelineState? {
        return makeBaseUnprojectionPipelineState(shaderFuncName: "unprojectCartesianVertex")
    }

    public func makeCylindricalUnprojectPipelineState() -> MTLRenderPipelineState? {
        return makeBaseUnprojectionPipelineState(shaderFuncName: "unprojectCylindricalVertex")
    }
    
    public func makeSingleFrameUnprojectPipelineState() -> MTLRenderPipelineState? {
        return makeBaseUnprojectionPipelineState(shaderFuncName: "unprojectSingleFrameVertex")
    }
    
    private func makeBaseGridPipelineState(functions: [String]) -> MTLRenderPipelineState? {
        guard let vertexFunction = library.makeFunction(name: functions[0]),
              let fragmentFunction = library.makeFunction(name: functions[1]) else { return nil }
        
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
    
	public func makeCartesianGridPipelineState() -> MTLRenderPipelineState? {
		return makeBaseGridPipelineState(functions: ["gridCartesianMeshVertex", "gridFragment"])
	}
	
    public func makeCylindricalGridPipelineState() -> MTLRenderPipelineState? {
        return makeBaseGridPipelineState(functions: ["gridCylindricalMeshVertex", "gridFragment"])
    }
	
	public func makeMetricsFootPipelineState() -> MTLRenderPipelineState? {
		return makeBaseGridPipelineState(functions: ["metricVertex", "gridFragment"])
	}
    
    public func makeSingleFramePipelineState() -> MTLRenderPipelineState? {
        return makeBaseGridPipelineState(functions: ["singleFrameVertex", "gridFragment"])
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

