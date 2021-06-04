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




kernel void computeFootMetric(
						   uint index [[ thread_position_in_grid ]],
						   device MyMeshData *myMeshData [[ buffer(kMyMesh) ]],
						   device GridPoint* heel [[ buffer(kBackHeel) ]],
						   device GridPoint* toe [[ buffer(kFrontToe) ]],
						   constant MetricIndeces& metricIndeces [[ buffer(kMetricIndeces) ]]
						   ) {
	const int i = index/PHI_GRID_NODE_COUNT;
	const auto i0 = metricIndeces.iHeights[0];
	const auto i1 = metricIndeces.iHeights[1];
	
	if ( i < i0 || i > i1 ) {
		return;
	}
	
	const int j = index%PHI_GRID_NODE_COUNT;
	device GridPoint* gp;
	if ( j == metricIndeces.jPhiHeel ) {
		gp = heel;
	} else if ( j == metricIndeces.jPhiToe ) {
		gp = toe;
	} else {
		return;
	}
	
	auto p = GridPoint();
	p.index = index;
	p.rho = myMeshData[index].mean;
	p.checked = 0;
	gp[i - i0] = p;
	
}
