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

#define MAX_MESH_STATISTIC 100
#define STATISTICS_THRESHOLD 3e-3

#define RADIUS 0.25
#define GRID_NODE_COUNT 1000
#define POINT_SIZE 12
#define EPS_H 3e-3
#define MAX_GRAD_H 7e-3

#define GRID_NODE_DISTANCE ((2*RADIUS) / GRID_NODE_COUNT)

#define GROUPS_COUNT 3

    enum Group {
        Unknown,
        Floor,
        Foot
    };

    enum ProjectionView {
        Up,
        Left,
        Right,
        Front,
        Back
    };

    struct MyMeshData {
        float heights[MAX_MESH_STATISTIC];
        int length;
        enum Group group;
        float gradient;
        int complete;
    };
    
    struct MyMeshData initMyMeshData(void);

    struct MyMeshData setAll(float value, int len, enum Group group);
   
    void setGroup(struct MyMeshData md, enum Group group);

    float getMedian(struct MyMeshData md);

    int gridRow(int index, int colNum);
    int gridColumn(int index, int colNum);
//    float toCoordinate(int pos, enum ProjectionView projection);
    int indexPos(int row, int column);

#ifdef __cplusplus
}
#endif

#endif /* MyMeshData_h */
