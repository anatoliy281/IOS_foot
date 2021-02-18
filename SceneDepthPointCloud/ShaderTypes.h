/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Types and enums that are shared between shaders and the host app code.
*/

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>

enum TextureIndices {
    kTextureY = 0,
    kTextureCbCr = 1,
    kTextureDepth = 2,
    kTextureConfidence = 3
};

enum BufferIndices {
    kPointCloudUniforms = 0,
    kParticleUniforms = 1,
    kGridPoints = 2,
    kMesh = 3,
    kTableIndexes = 4,
    kMyMesh = 5
};

struct RGBUniforms {
    matrix_float3x3 viewToCamera;
    float viewRatio;
    float radius;
};

struct PointCloudUniforms {
    matrix_float4x4 viewProjectionMatrix;
    matrix_float4x4 localToWorld;
    matrix_float3x3 cameraIntrinsicsInversed;
    simd_float2 cameraResolution;
    
    float particleSize;
    int maxPoints;
    int pointCloudCurrentIndex;
    int confidenceThreshold;
};

struct ParticleUniforms {
    simd_float3 position;
    simd_float3 color;
    float confidence;
};

struct MeshData {
    simd_float3 position;
};

#define MAX_MESH_STATISTIC 40

#define RADIUS 0.5
#define GRID_NODE_COUNT 500

#define GRID_NODE_DISTANCE ((2*RADIUS) / GRID_NODE_COUNT)

struct MyMeshData {
    float heights[MAX_MESH_STATISTIC];
//    float heights;
//    metal::array<float, MAX_MESH_STATISTIC> heights;
    int length;
};

#endif /* ShaderTypes_h */
