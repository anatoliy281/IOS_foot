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
	

	void moreModification(float value);
	
	void cycle();
	int incrementModulo(int x, int step = 1);
//	float moveMedian(int greater);
//	int detectShiftDirection(float median, float a, float b, bool add);
	
public:
	MedianSearcher(device MyMeshData* meshData): md(meshData), mdConst(nullptr) {}
	MedianSearcher(constant MyMeshData* meshData): md(nullptr), mdConst(meshData) {}
	void oldCode(float value);
	
	void newValue(float value);
	
	void newValueModi(float value);
	
};

void MedianSearcher::cycle() {
	md->bufModLen = incrementModulo(md->bufModLen);
	md->totalSteps += 1;
}

int MedianSearcher::incrementModulo(int x, int step) {
	return (x + step + MAX_MESH_STATISTIC)%MAX_MESH_STATISTIC;
}


void MedianSearcher::newValue(float value) {
	
//	modification(value);
	
	oldCode(value);
}

void MedianSearcher::oldCode(float value) {
	device auto& mean = md->mean;
	
	int n = md->bufModLen;
	md->buffer[n] = value;
	cycle();
	if ( md->bufModLen == md->totalSteps ) {
		mean = (mean*n + value) / (n + 1.f);
	} else {
		float newMean = 0;
		
		for (int i = 0; i < MAX_MESH_STATISTIC; ++i) {
			newMean += md->buffer[i];
		}
		newMean /= MAX_MESH_STATISTIC;
		mean = newMean;
	}
}

void MedianSearcher::newValueModi(float value) {
	device auto& mean = md->mean;
	
	cycle();	// пересчёт индекса массива с учётом цикличности!
	
//	md->totalSteps += 1;
	if ( md->totalSteps <= MAX_MESH_STATISTIC ) { // md->totalStep пересчитан!!! и мы на первой итерации циклич. списка, т.е. продолжаем его заполнение пока его длина не достигнет MAX_MESH_STATISTIC
		int n = md->totalSteps;	// здесь 1 <= n <= (MAX_MESH_STATISTIC - 1)
		mean = (mean*(n-1) + value) / n;
		md->buffer[n-1] = value;	// пополнили буфер для нужд пересчёта при проходе по циклическим шагам
	} else {
		const auto nc = md->bufModLen;
//		const auto nc = md->totalSteps%MAX_MESH_STATISTIC;
		const auto oldValue = md->buffer[nc-1];
		md->buffer[nc-1] = value;
		mean += ((value - oldValue) / MAX_MESH_STATISTIC);
	}
	
}


void MedianSearcher::moreModification(float value) {
	device auto& mean = md->mean;
	
	cycle();	// пересчёт индекса массива с учётом цикличности!
	
	const auto nc = md->bufModLen;
	const auto oldValue = md->buffer[nc-1];
	md->buffer[nc-1] = value;
	mean += ((value - oldValue) / MAX_MESH_STATISTIC);
	
}
