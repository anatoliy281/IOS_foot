//
//  computeNormals.metal
//  SceneDepthPointCloud
//
//  Created by Анатолий Чернов on 17.05.2021.
//  Copyright © 2021 Apple. All rights reserved.
//

#include <metal_stdlib>
#include <simd/simd.h>
#include "../MyMeshData.h"
#import "../ShaderTypes.h"

float4 fromGiperbolicToCartesian(float value, int index);

using namespace metal;

kernel void processSegmentation(
						   uint index [[ thread_position_in_grid ]],
						   device MyMeshData *myMeshData [[ buffer(kMyMesh) ]]
						   ) {
	device auto& mesh = myMeshData[index];
	const auto r0 = fromGiperbolicToCartesian(mesh.mean, index);
	
//	const int i = index/PHI_GRID_NODE_COUNT;
//	const int j = index%PHI_GRID_NODE_COUNT;
//
}
