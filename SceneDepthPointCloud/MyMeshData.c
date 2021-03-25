//
//  MyMeshData.c
//  SceneDepthPointCloud
//
//  Created by iOSdev on 18.02.2021.
//  Copyright © 2021 Apple. All rights reserved.
//

#include "MyMeshData.h"
#include <stdio.h>
#include <assert.h>

float getMedian(struct MyMeshData md) {
    return md.heights[md.length/2];
}

int isCulculated(struct MyMeshData md) {
    return md.length > 0;
}

struct MyMeshData initMyMeshData() {
    return setAll(-0.5, 0, Unknown);
}

struct MyMeshData setAll(float value, int len, enum Group group) {
    assert(len < MAX_MESH_STATISTIC);
    struct MyMeshData md;
    md.group = group;
    md.length = len;
    for (int i=0; i < MAX_MESH_STATISTIC; ++i) {
        md.heights[i] = value;
    }
    return md;
}

void setGroup(struct MyMeshData md, enum Group group) {
    md.group = group;
}

int gridRow(int index, int colNum) {
    return index / colNum;
}

int gridColumn(int index, int colNum) {
    return index % colNum;
}

//float toCoordinate(int pos, enum ProjectionView projection) {
//    float res;
//    if (projection == Up) {
//        res = pos*GRID_NODE_DISTANCE - RADIUS;
//    }
//    
//    return res;
//}

int indexPos(int row, int column) {
    return row * GRID_NODE_COUNT + column;
}
