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
bool inFootFrame(float4 spos);

using namespace metal;

constant auto gridTotalNodes = U_GRID_NODE_COUNT*PHI_GRID_NODE_COUNT;

float calcDzDrho(device MyMeshData* mesh,
					  int index,
					  int delta) {
	const auto stepIndex = delta*PHI_GRID_NODE_COUNT;
	
	const auto index0 = (index >= stepIndex) ? index - stepIndex: index;
	const auto val0 = mesh[index0].mean;
	const auto r0 = fromGiperbolicToCartesian(val0, index0);
	
	const auto indexN = (index < (gridTotalNodes - stepIndex)) ? index + stepIndex: index;
	const auto valN = mesh[indexN].mean;
	const auto rN = fromGiperbolicToCartesian(valN, indexN);
	
	const auto dR = r0 - rN;
	
	if (inFootFrame(r0) && inFootFrame(rN)) {
		return dR.z / length(dR.xy);
	} else {
		return 0;
	}
	
	
}

float calcH(device MyMeshData* mesh,
			int index) {
	device auto& value = mesh[index].mean;
	const auto r = fromGiperbolicToCartesian(value, index);
	return r.z;
}

kernel void processSegmentation(
						   uint index [[ thread_position_in_grid ]],
						   device MyMeshData *myMeshData [[ buffer(kMyMesh) ]]
						   ) {
	device auto& mesh = myMeshData[index];
	const auto deltaN = 2;
	const auto criticalSlope = 1;
	const auto criticalFloorHeight = 0.005;
	const auto criticalBorderHeight = 0.03;
	
	const auto h = calcH(myMeshData, index);
	const auto s = calcDzDrho(myMeshData, index, deltaN);

	if ( s > criticalSlope && h < criticalBorderHeight ) {
		mesh.group = Border;
	} else if ( h > criticalBorderHeight ) {
		mesh.group = Foot;
	} else if ( s < criticalSlope || h <= criticalFloorHeight ) {
		mesh.group = Floor;
	} else {
		mesh.group = Unknown;
	}
	
}
