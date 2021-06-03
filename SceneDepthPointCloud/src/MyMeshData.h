#ifndef MyMeshData_h
#define MyMeshData_h

#ifdef __cplusplus
extern "C" {
#endif

#define MAX_MESH_STATISTIC 21

#define RADIUS 0.5
#define GRID_NODE_COUNT 500
#define POINT_SIZE 12
#define EPS_H 3e-3
#define MAX_GRAD_H 27e-3
#define PI 3.14159

#include <simd/simd.h>


#define PHI_STEP ((2*PI) / GRID_NODE_COUNT)
#define GRID_NODE_DISTANCE ((2*RADIUS) / GRID_NODE_COUNT)

#define GROUPS_COUNT 3

#define Z_NODE_DIST ((RADIUS) / GRID_NODE_COUNT)



#define PAIR_SIZE 256
    enum Group {
        Unknown,
        Floor,
        Foot
    };

    struct MyMeshData {

		int lock;
        float buffer[MAX_MESH_STATISTIC];  	// актуальные данные буфера
        int bufModLen;                         // текущее значение для заполнения
		int totalSteps;					// текущая длина буфера без модульного деления
        float pairs[PAIR_SIZE];       				// поступающая пара для пересчета медианы
        int pairLen;                        // длина промежуточного буфера пар
		int debugCall;

		float depth;						// глубина
		float gradVal;
        enum Group group;
		simd_float3 normal;
		float mean;
		float meanSquared;
    };
    
    struct MyMeshData initMyMeshData(float valInit);

    int gridRow(int index);
    int gridColumn(int index);
    float calcX(int j, float val);
    float calcY(int j, float val);
    float calcZ(int i);
    int indexPos(int row, int column);

    float toCoordinate(int pos);

#ifdef __cplusplus
}
#endif

#endif /* MyMeshData_h */
