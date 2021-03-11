//
//  MyMeshData.h
//  SceneDepthPointCloud
//
//  Created by iOSdev on 18.02.2021.
//  Copyright © 2021 Apple. All rights reserved.
//

#ifndef MyMeshData_h
#define MyMeshData_h

#ifdef __cplusplus
extern "C" {
#endif

    #define MAX_MESH_STATISTIC 40

    #define RADIUS 0.5
    #define GRID_NODE_COUNT 500

    #define GRID_NODE_DISTANCE ((2*RADIUS) / GRID_NODE_COUNT)

    #define GROUPS_COUNT 3

    enum Group {
        Unknown,
        Floor,
        Foot
    };

    struct MyMeshData {
        float heights[MAX_MESH_STATISTIC];
        int length;
        enum Group group;
    };
    
    struct MyMeshData initMyMeshData(void);

    struct MyMeshData setAll(float value, int len, enum Group group);
   
    void setGroup(struct MyMeshData md, enum Group group);

    float getMedian(struct MyMeshData md);

    int gridRow(int index);
    int gridColumn(int index);
    float toCoordinate(int pos);
    int indexPos(int row, int column);

#ifdef __cplusplus
}
#endif

#endif /* MyMeshData_h */
