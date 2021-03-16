/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Types and enums that are shared between shaders and the host app code.
*/

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>
#include "MyMeshData.h"

enum TextureIndices {
    kTextureDepth = 2,
    kTextureConfidence = 3
};

enum BufferIndices {
    kPointCloudUniforms = 0,
    kGridPoints = 1,
    kMyMesh = 2,
    kHeight = 3,
    kLayer = 4
};

struct PointCloudUniforms {
    matrix_float4x4 viewProjectionMatrix;
    matrix_float4x4 localToWorld;
    matrix_float3x3 cameraIntrinsicsInversed;
    simd_float2 cameraResolution;
};

typedef struct {
    float floor;
    float delta;
} Heights;


#endif /* ShaderTypes_h */
