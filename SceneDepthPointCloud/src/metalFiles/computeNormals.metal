//
//  computeNormals.metal
//  SceneDepthPointCloud
//
//  Created by Анатолий Чернов on 17.05.2021.
//  Copyright © 2021 Apple. All rights reserved.
//

#include <metal_stdlib>
#include "../MyMeshData.h"
#import "../ShaderTypes.h"

using namespace metal;

constant int gridNodeCount = GRID_NODE_COUNT;		// 500
constant float halfLength = RADIUS;					// 0.5
constant float gridNodeDist = halfLength / gridNodeCount;

float3 restoreNode(device MyMeshData* meshData, uint index, uint i, uint j) {
	const auto indexIJ = index + i*GRID_NODE_COUNT + j;
	const auto rho = meshData[indexIJ].median;
	const auto z = (index/GRID_NODE_COUNT + i)*gridNodeDist;
	const auto phi = (index%GRID_NODE_COUNT + j)*PHI_STEP;
	
	float3 pos;
	pos.x = rho*cos(phi);
	pos.y = rho*sin(phi);
	pos.z = z;

	return pos;
}

//void cleanNode(device MyMeshData* meshData, uint index) {
//	float rhos[9];
//	rhos[0] = meshData[index].median;
//	rhos[1] = meshData[index + 1].median;
//	rhos[2] = meshData[index - 1].median;
//	rhos[3] = meshData[index + GRID_NODE_COUNT].median;
//	rhos[4] = meshData[index + GRID_NODE_COUNT + 1].median;
//	rhos[5] = meshData[index + GRID_NODE_COUNT - 1].median;
//	rhos[6] = meshData[index - GRID_NODE_COUNT].median;
//	rhos[7] = meshData[index - GRID_NODE_COUNT + 1].median;
//	rhos[8] = meshData[index - GRID_NODE_COUNT - 1].median;
//
//	for (int i=1; i < 9; ++i) {
//		if ( abs(rhos[i] - rhos[0]) > 0.005) {
//			rhos[i] = rhos[0];
//		}
//	}
//}

kernel void computeNormals(
						   uint index [[ thread_position_in_grid ]],
						   device MyMeshData *myMeshData [[ buffer(kMyMesh) ]]
						   ) {
	const auto nC = GRID_NODE_COUNT;
	device auto& md = myMeshData[index];
	const auto i = index/nC;
	if ( 0 < i && i < nC - 1) { // отступаем для расчёта нормалей
		auto r0 = restoreNode(myMeshData, index, 0, 0); // центральный узел
		const auto r1 = restoreNode(myMeshData, index, 0, -1);
		const auto r2 = restoreNode(myMeshData, index, 1, 0);
		const auto r3 = restoreNode(myMeshData, index, 0, 1);
		const auto r4 = restoreNode(myMeshData, index, -1, 0);
		
		r0 = (r0 + r1 + r2 + r3 + r4) / 5;
		
		float3 normal(0);
		normal += cross(r1 - r0, r4 - r0);
		normal += cross(r2 - r0, r1 - r0);
		normal += cross(r3 - r0, r2 - r0);
		normal += cross(r4 - r0, r1 - r0);

		md.normal = normalize(normal);
	}
	
}
