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
	if (val0 == 0) {
		return 0;
	}
	const auto r0 = fromGiperbolicToCartesian(val0, index0);
	
	const auto indexN = (index < (gridTotalNodes - stepIndex)) ? index + stepIndex: index;
	const auto valN = mesh[indexN].mean;
	if (valN == 0) {
		return 0;
	}
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


constant float EpsilonSqured = 0.003*0.003;

kernel void processSegmentation(
						   uint index [[ thread_position_in_grid ]],
						   device MyMeshData *myMeshData [[ buffer(kMyMesh) ]],
						   constant float3& pointInRise [[ buffer(kRisePoint) ]],
						   device BorderPoints* borderBuffer [[ buffer(kBorderBuffer) ]]
						   ) {
	device auto& mesh = myMeshData[index];
	
	if (mesh.mean == 0) {
		return;
	}
	
	const auto deltaN = 3;
	const auto criticalSlope = 1;
//	const auto criticalFloorHeight = 0.005;
	const auto criticalBorderHeight = 0.03;
	
	const auto j = index%PHI_GRID_NODE_COUNT;
	device auto& bp = borderBuffer[j];
//	bp.typePoint = none;
	
	const auto s = calcDzDrho(myMeshData, index, deltaN);
	const auto r = calcCoord(myMeshData, index);
	const auto h = r.z;

	if ( s > criticalSlope &&
		 h < criticalBorderHeight &&
		 length_squared(r.xy) > 0.02*0.02 ) {
		mesh.group = Border;
		const auto i = (bp.len++)%MAX_BORDER_POINTS;
		bp.coords[i] = float4(r, index/PHI_GRID_NODE_COUNT);
//		bp.tgAlpha[i] = s;
	} else if (bp.u_coord != 0) {
		auto xyOut = int(index/PHI_GRID_NODE_COUNT) > bp.u_coord;
		if ( xyOut ) {
			mesh.group = Floor;
		} else {
			mesh.group = Foot;
		}
	} else  {
		if (h > criticalBorderHeight) {
			mesh.group = Foot;
		} else {
			mesh.group = Unknown;
		}
	}
	
	// TODO доделать взятие области 
	if ( length_squared(r.xy - pointInRise.xy) < EpsilonSqured ) {	// заполняем буфер в области подъёма
		device auto& bpCenter = borderBuffer[PHI_GRID_NODE_COUNT+9];
		bpCenter.coords[(bpCenter.len++)%MAX_BORDER_POINTS] = float4(r, 0);
	}
	
}

// реализация нахождения границы
kernel void reductBorderBuffer(
							   uint index[[ thread_position_in_grid ]],
							   device BorderPoints* buffer[[ buffer(kBorderBuffer) ]]
							   ) {
	if ( index == PHI_GRID_NODE_COUNT+9 ) { // не понятно почему не проходит усреднение, поэтому код закомментирован
		device auto& bp = buffer[index];
		float4 mean = 0;
//		for (int i=0; i < MAX_BORDER_POINTS; ++i) {
//			mean += bp.coords[i];
//		}
//		mean /= MAX_BORDER_POINTS;
		bp.mean = mean.xyz;
	} else if ( index > PHI_GRID_NODE_COUNT  ) {
		return;
	} else {
		device auto& bp = buffer[index];
	//	auto len = min(bp.len, MAX_BORDER_POINTS);
		auto len = MAX_BORDER_POINTS;
	//	if (len != MAX_BORDER_POINTS) {
	//		return;
	//	}

		float4 mean = 0;
		auto cnt = 0;
//		auto maxTangent = 0;
//		auto iMaxTangent = 0;
		for (int i=0; i < len; ++i) {
			if (length_squared(bp.coords[i]) > 0) {
				mean += bp.coords[i];
				++cnt;
			}
//			if (maxTangent < bp.tgAlpha[i]) {
//				maxTangent = bp.tgAlpha[i];
//				iMaxTangent = i;
//			}
		}
		mean /= cnt;


		bp.mean = mean.xyz;
//		bp.mean = bp.coords[iMaxTangent].xyz;
		bp.typePoint = border;
		bp.u_coord = int(mean.w);
	}
}
