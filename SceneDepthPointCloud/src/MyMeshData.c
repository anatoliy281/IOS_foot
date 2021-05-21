#include "MyMeshData.h"
#include <stdio.h>
#include <assert.h>
#include <math.h>

struct MyMeshData initMyMeshData(float valInit) {
	struct MyMeshData md;
	md.lock = 0;
	for (int i=0; i < MAX_MESH_STATISTIC; ++i) {
		md.buffer[i] = valInit;
	}
	md.bufModLen = 0;
	md.totalSteps = 0;
	md.pairs[0] = 0;
	md.pairs[1] = 0;
	md.pairLen = 0;
	md.debugCall = 0;
	md.median = valInit;
	md.group = Unknown;
	return md;
}

int gridRow(int index) {
    return index / GRID_NODE_COUNT;
}

int gridColumn(int index) {
    return index % GRID_NODE_COUNT;
}

float toCoordinate(int pos) {
    return pos*GRID_NODE_DISTANCE - RADIUS;
}

int indexPos(int row, int column) {
    return row * GRID_NODE_COUNT + column;
}


float calcX(/*int i, */int j, float val) {
    
//    float rho = val;
//    float theta = i*THETA_STEP;
//    float phi = j*PHI_STEP;
//
//    return rho*sin(theta)*cos(phi);
	
	float rho = val;
//	float theta = i*THETA_STEP;
	float phi = j*PHI_STEP;
	
	return rho*cos(phi);
}
float calcY(/*int i, */int j, float val) {
//    float rho = val;
//    float theta = i*THETA_STEP;
//    float phi = j*PHI_STEP;
//
//    return rho*sin(theta)*sin(phi);
	float rho = val;
	float phi = j*PHI_STEP;

	return rho*sin(phi);
}
float calcZ(int i/*, int j, float val*/) {
//    float rho = val;
//    float theta = i*THETA_STEP;
//
//    return rho*cos(theta);
	return i*RADIUS/GRID_NODE_COUNT;
}

