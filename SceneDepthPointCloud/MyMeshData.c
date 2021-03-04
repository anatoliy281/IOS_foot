//
//  MyMeshData.c
//  SceneDepthPointCloud
//
//  Created by iOSdev on 18.02.2021.
//  Copyright © 2021 Apple. All rights reserved.
//

#include "MyMeshData.h"
#include <stdio.h>

float getMedian(struct MyMeshData md) {
    return md.heights[md.length/2];
}

int isCulculated(struct MyMeshData md) {
    return md.length > 0;
}

struct MyMeshData initMyMeshData() {
    struct MyMeshData md;
    for (int i=0; i < MAX_MESH_STATISTIC; ++i) {
        md.heights[i] = -0.5;
    }
    md.group = Unknown;
    md.length = 0;
    return md;
}

void setGroup(struct MyMeshData md, enum Group group) {
    md.group = group;
}


//float gridXCoord(int index) {
//    return (index/GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
//}
//
//float gridZCoord(int index) {
//    return (index%GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
//}

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
