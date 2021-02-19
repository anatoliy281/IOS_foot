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

void setGroup(struct MyMeshData md, enum Group group) {
    md.group = group;
}


float gridXCoord(int index) {
    return (index/GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
}

float gridZCoord(int index) {
    return (index%GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
}
