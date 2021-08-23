#ifndef MyMeshData_h
#define MyMeshData_h

#ifdef __cplusplus
extern "C" {
#endif

#define MAX_MESH_STATISTIC 21

// cartesian grid
#define RADIUS 0.5
#define GRID_NODE_COUNT 500

#define POINT_SIZE 12
#define EPS_H 3e-3
#define MAX_GRAD_H 27e-3

#include <simd/simd.h>



#define GROUPS_COUNT 3

// giperbolic grid
#define PHI_GRID_NODE_COUNT 200
#define PHI_STEP ((2*M_PI_F) / PHI_GRID_NODE_COUNT)

//#define U0_GRID_NODE_COUNT 200
//#define U1_GRID_NODE_COUNT 650
#define U_GRID_NODE_COUNT 100
//#define LENGTH 0.25
//#define U_STEP ((LENGTH*LENGTH) / (U_GRID_NODE_COUNT))
#define U_STEP 0.0005

//#define V_GRID_NODE_COUNT U_GRID_NODE_COUNT
//#define V_STEP U_STEP

// 

// foot frame bounding rectangle
#define BOX_HALF_LENGTH 0.185
#define BOX_HALF_WIDTH 0.08
#define BOX_HEIGHT 0.1
//#define BOX_BACK_LENGTH 0.07
//#define BOX_FRONT_LENGTH 0.3
#define BOX_FLOOR_ZONE 0.03
//#define HEIGHT_OVER_FLOOR 0.03



// number border points
#define MAX_BORDER_POINTS 28

    enum Group {
        Unknown,
        Floor,
		FloorMarker,
        Foot,
		ZoneUndefined,
		FootDefect
    };

    struct MyMeshData {
		int justRefilled;
		short sectorNumber;
        float buffer[MAX_MESH_STATISTIC];  	// актуальные данные буфера
		int totalSteps;					// текущая длина буфера без модульного деления
		float heightCorrection;			// поправка по высоте

        enum Group group;
		simd_float3 normal;
		float mean;
		float meanSquared;
    };
    
    struct MyMeshData initMyMeshData(float valInit);

    long gridRow(long index);
    long gridColumn(long index);

#ifdef __cplusplus
}
#endif

#endif /* MyMeshData_h */
