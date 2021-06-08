#ifndef MyMeshData_h
#define MyMeshData_h

#ifdef __cplusplus
extern "C" {
#endif

#define MAX_MESH_STATISTIC 41

// cartesian grid
#define RADIUS 0.5
#define GRID_NODE_COUNT 500

#define POINT_SIZE 12
#define EPS_H 3e-3
#define MAX_GRAD_H 27e-3

#include <simd/simd.h>



#define GROUPS_COUNT 3

// giperbolic grid
#define PHI_GRID_NODE_COUNT 100
#define PHI_STEP ((2*M_PI_F) / PHI_GRID_NODE_COUNT)
#define U0_GRID_NODE_COUNT 150
#define U1_GRID_NODE_COUNT 350
#define SQUARED_LENGTH 0.5
#define U_GRID_NODE_COUNT (U0_GRID_NODE_COUNT+U1_GRID_NODE_COUNT)
#define U_STEP ((SQUARED_LENGTH*SQUARED_LENGTH) / U_GRID_NODE_COUNT)

#define PAIR_SIZE 256
    enum Group {
        Unknown,
        Floor,
        Foot
    };

    struct MyMeshData {
		int isDone;
        float buffer[MAX_MESH_STATISTIC];  	// актуальные данные буфера
        int bufModLen;                         // текущее значение для заполнения
		int totalSteps;					// текущая длина буфера без модульного деления

        enum Group group;
		simd_float3 normal;
		float mean;
		float meanSquared;
    };
    
    struct MyMeshData initMyMeshData(float valInit);

//    int gridRow(int index);
//    int gridColumn(int index);
//    float calcX(int j, float val);
//    float calcY(int j, float val);
//    float calcZ(int i);
//    int indexPos(int row, int column);

//    float toCoordinate(int pos);

#ifdef __cplusplus
}
#endif

#endif /* MyMeshData_h */
