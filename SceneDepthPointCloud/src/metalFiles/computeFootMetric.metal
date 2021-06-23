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
	if (length(r0.xy) > length(rN.xy)) {
		return 0;
	}
	
	if (inFootFrame(r0) && inFootFrame(rN)) {
		return dR.z / length(dR.xy);
	} else {
		return 0;
	}
	
	
}

float3 calcCoord(device MyMeshData* mesh,
			int index) {
	device auto& value = mesh[index].mean;
	const auto r = fromGiperbolicToCartesian(value, index);
	return r.xyz;
}

kernel void processSegmentation(
						   uint index [[ thread_position_in_grid ]],
						   device MyMeshData *myMeshData [[ buffer(kMyMesh) ]],
						   device BorderPoints* borderBuffer [[ buffer(kBorderBuffer) ]]
						   ) {
	device auto& mesh = myMeshData[index];
	const auto deltaN = 2;
	const auto criticalSlope = 1;
	const auto criticalFloorHeight = 0.005;
	const auto criticalBorderHeight = 0.03;
	
	const auto j = index%PHI_GRID_NODE_COUNT;
	device auto& bp = borderBuffer[j];
	bp.typePoint = none;
	
	const auto borderHeight = (bp.mean.z == 0 ) ? criticalBorderHeight : bp.mean.z;
	const auto floorHeight = (bp.mean.z == 0 ) ? criticalFloorHeight : bp.mean.z;
	
	const auto s = calcDzDrho(myMeshData, index, deltaN);
	const auto r = calcCoord(myMeshData, index);
	const auto h = r.z;

	if ( s > criticalSlope && h < criticalBorderHeight ) {
		mesh.group = Border;
		bp.coords[(bp.len++)%MAX_BORDER_POINTS] = r;
	} else if ( h > borderHeight ) {
		mesh.group = Foot;
	} else if ( s < criticalSlope || h <= floorHeight ) {
		mesh.group = Floor;
	} else {
		mesh.group = Unknown;
	}
	
}

// реализация нахождения границы
kernel void reductBorderBuffer(
							   uint index[[ thread_position_in_grid ]],
							   device BorderPoints* buffer[[ buffer(kBorderBuffer) ]]
							   ) {
	if (index >= PHI_GRID_NODE_COUNT) {
		return;
	}
	device auto& bp = buffer[index];
//	auto len = min(bp.len, MAX_BORDER_POINTS);
	auto len = MAX_BORDER_POINTS;
	if (len != MAX_BORDER_POINTS) {
		return;
	}
	float3 mean = 0;
	auto cnt = 0;
	for (int i=0; i < len; ++i) {
		if (length_squared(bp.coords[i]) > 0) {
			mean += bp.coords[i];
			++cnt;
		}
	}
	mean /= cnt;
	
	bp.mean = mean;
}
