//
//  depricatedFunctions.metal
//  SceneDepthPointCloud
//
//  Created by Анатолий Чернов on 15.06.2021.
//  Copyright © 2021 Apple. All rights reserved.
//

#include <metal_stdlib>
#include "../ShaderTypes.h"

using namespace metal;

constexpr sampler depthSampler;

// вычисление  угла градиента
float calcGrad(uint vid,
				constant float2 *gridPoints,
				constant PointCloudUniforms &uniforms,
				texture2d<float, access::sample> depthTexture,
				int imgWidth,
				int imgHeight) {
	
	float res = 0;
	if (
		static_cast<unsigned int>(imgWidth) <= vid &&
		vid < static_cast<unsigned int>(imgWidth*(imgHeight - 1))
		) {
		
		const auto v11 = vid;

		const auto v01 = v11 - imgWidth; // изменение вдоль Y
		const auto v00 = v01 - 1;
		const auto v02 = v01 + 1;
		
		const auto v10 = v11 - 1;
		const auto v12 = v11 + 1;
		
		const auto v21 = v11 + imgWidth; // изменение вдоль Y
		const auto v20 = v21 - 1;
		const auto v22 = v21 + 1;
		
		
		
		const auto t00 = gridPoints[v00] / uniforms.cameraResolution;
		const auto t01 = gridPoints[v01] / uniforms.cameraResolution;
		const auto t02 = gridPoints[v02] / uniforms.cameraResolution;
//		const auto t11 = gridPoints[v11] / uniforms.cameraResolution;
		const auto t10 = gridPoints[v10] / uniforms.cameraResolution;
		const auto t12 = gridPoints[v12] / uniforms.cameraResolution;
		
		const auto t20 = gridPoints[v20] / uniforms.cameraResolution;
		const auto t21 = gridPoints[v21] / uniforms.cameraResolution;
		const auto t22 = gridPoints[v22] / uniforms.cameraResolution;
		
		const auto dr = float2((t00 - t02).x, (t02 - t22).y);
		
		// Sample the depth map to get the depth value
		const auto f00 = depthTexture.sample(depthSampler, t00).r;
		const auto f01 = depthTexture.sample(depthSampler, t01).r;
		const auto f02 = depthTexture.sample(depthSampler, t02).r;
		const auto f10 = depthTexture.sample(depthSampler, t10).r;
		const auto f12 = depthTexture.sample(depthSampler, t12).r;
		const auto f20 = depthTexture.sample(depthSampler, t20).r;
		const auto f21 = depthTexture.sample(depthSampler, t21).r;
		const auto f22 = depthTexture.sample(depthSampler, t22).r;
		
		const auto df = 0.25*float2(f00 - f20 + 2*(f01 - f21) + f02 - f22,
							   f02 - f00 + 2*(f12 - f10) + f22 - f20);
		res = atan ( sqrt( dot(df, df) / dot(dr, dr) ) );
	}
	return res;
}

