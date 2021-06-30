#include "MyMeshData.h"
#include <stdio.h>
#include <assert.h>
#include <math.h>

struct MyMeshData initMyMeshData(float valInit) {
	struct MyMeshData md;
	for (int i=0; i < MAX_MESH_STATISTIC; ++i) {
		md.buffer[i] = valInit;
	}
	md.bufModLen = 0;
	md.totalSteps = 0;
	md.isDone = 0;

	md.mean = valInit;
	md.group = Unknown;
	return md;
}

int gridRow(int index) {
    return index / PHI_GRID_NODE_COUNT;
}

int gridColumn(int index) {
    return index % PHI_GRID_NODE_COUNT;
}

