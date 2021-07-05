//
//  MedianSearcher.metal
//  SceneDepthPointCloud
//
//  Created by Анатолий Чернов on 15.06.2021.
//  Copyright © 2021 Apple. All rights reserved.
//

#include <metal_stdlib>
#include "../MyMeshData.h"
using namespace metal;



class MedianSearcher {
	device MyMeshData* md;
	constant MyMeshData* mdConst;

	void update(float value);
	
public:
	MedianSearcher(device MyMeshData* meshData): md(meshData), mdConst(nullptr) {}
	MedianSearcher(constant MyMeshData* meshData): md(nullptr), mdConst(meshData) {}

	
	void newValue(float value);
	void newValue(float value, int count);
	
};


void MedianSearcher::newValue(float value) {
	update(value);
}

void MedianSearcher::newValue(float value, int count) {
	for (int i=0; i < count; ++i) {
		update(value);
	}
}


void MedianSearcher::update(float value) {
	device auto& mean = md->mean;
	device auto& totalSteps = md->totalSteps;
	
	int n = totalSteps%MAX_MESH_STATISTIC;
	const auto saved = md->buffer[n];
	md->buffer[n] = value;

	if ( totalSteps < MAX_MESH_STATISTIC ) {
		mean = (mean*n + value) / (n + 1.f);
	} else {
		float newMean = 0;
		for (int i = 0; i < MAX_MESH_STATISTIC; ++i) {
			newMean += md->buffer[i];
		}
		newMean /= MAX_MESH_STATISTIC;
		mean = newMean;
		
//		mean += (value - saved)/MAX_MESH_STATISTIC;
	}
	++totalSteps;
}

