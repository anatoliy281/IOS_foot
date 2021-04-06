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
    kTextureY = 0,
    kTextureCbCr = 1,
    kTextureDepth = 2,
    kTextureConfidence = 3
};

enum BufferIndices {
    kPointCloudUniforms = 0,
    kGridPoints = 1,
    kMyMesh = 2,
    kHeight = 3,
    kVerteces = 4,
    kViewCorner = 5,
    kViewToCam = 6,
    kLayer = 7,
    kHeelArea = 8
};

struct PointCloudUniforms {
    matrix_float4x4 viewProjectionMatrix;
    matrix_float4x4 localToWorld;
    matrix_float3x3 cameraIntrinsicsInversed;
    simd_float2 cameraResolution;
};

struct ColoredPoint {
    simd_float3 position;
    simd_int4 color;
};

struct CameraView {
    simd_float2 viewVertices;
    simd_float2 viewTexCoords;
};



#endif /* ShaderTypes_h */
