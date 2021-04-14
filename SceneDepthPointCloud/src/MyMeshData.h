#ifndef MyMeshData_h
#define MyMeshData_h

#ifdef __cplusplus
extern "C" {
#endif

#define MAX_MESH_STATISTIC 200

#define RADIUS 0.5
#define GRID_NODE_COUNT 500
#define POINT_SIZE 12
#define EPS_H 3e-3
#define MAX_GRAD_H 27e-3
#define PI 3.14159


#define PHI_STEP ((2*PI) / GRID_NODE_COUNT)
#define THETA_STEP ((PI/2) / GRID_NODE_COUNT)
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
//    void calcXY(int i, int j, float* x, float* y);
    float calcX(int i, int j, float val);
    float calcY(int i, int j, float val);
    float calcZ(int i, int j, float val);
    int indexPos(int row, int column);

    float toCoordinate(int pos);

#ifdef __cplusplus
}
#endif

#endif /* MyMeshData_h */
