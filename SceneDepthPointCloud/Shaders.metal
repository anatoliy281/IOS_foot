/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The sample app's shaders.
*/

//#include <algorithm>

#include <metal_stdlib>
#include <simd/simd.h>
#import "ShaderTypes.h"
#include "MyMeshData.h"
#include <metal_array>

using namespace metal;


// Camera's RGB vertex shader outputs
//struct RGBVertexOut {
//    float4 position [[position]];
//    float2 texCoord;
//};

//// Particle vertex shader outputs and fragment shader inputs
struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};
//
constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);
//constant auto yCbCrToRGB = float4x4(float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
//                                    float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
//                                    float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
//                                    float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f));
//constant float2 viewVertices[] = { float2(-1, 1), float2(-1, -1), float2(1, 1), float2(1, -1) };
//constant float2 viewTexCoords[] = { float2(0, 0), float2(0, 1), float2(1, 0), float2(1, 1) };

/// Retrieves the world position of a specified camera point with depth
static simd_float4 worldPoint(simd_float2 cameraPoint, float depth, matrix_float3x3 cameraIntrinsicsInversed, matrix_float4x4 localToWorld) {
    const auto localPoint = cameraIntrinsicsInversed * simd_float3(cameraPoint, 1) * depth;
    const auto worldPoint = localToWorld * simd_float4(localPoint, 1);
    
    return worldPoint / worldPoint.w;
}

int find_greater(float val, device float* ar, int len) {
    for (int i = 0; i < len; ++i) {
        if (ar[i] >= val)
            return i;
    }
    return len;
}

void shift_right(int pos, device float* ar, int len) {
    auto start = min(MAX_MESH_STATISTIC-1, len);
    for (int i = start; i > pos; --i) {
        ar[i] = ar[i-1];
    }
}

///  Vertex shader that takes in a 2D grid-point and infers its 3D position in world-space, along with RGB and confidence
vertex void unprojectVertex(uint vertexID [[vertex_id]],
                            constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
                            constant float2 *gridPoints [[ buffer(kGridPoints) ]],
                            device MyMeshData *myMeshData[[ buffer(kMyMesh) ]],

                            texture2d<float, access::sample> capturedImageTextureY [[texture(kTextureY)]],
                            texture2d<float, access::sample> capturedImageTextureCbCr [[texture(kTextureCbCr)]],
                            texture2d<float, access::sample> depthTexture [[texture(kTextureDepth)]],
                            texture2d<unsigned int, access::sample> confidenceTexture [[texture(kTextureConfidence)]]
                            ) {
    
    const auto gridPoint = gridPoints[vertexID];

    const auto texCoord = gridPoint / uniforms.cameraResolution;
    // Sample the depth map to get the depth value
    const auto depth = depthTexture.sample(colorSampler, texCoord).r;
    // With a 2D point plus depth, we can now get its 3D position
    const auto position = worldPoint(gridPoint, depth, uniforms.cameraIntrinsicsInversed, uniforms.localToWorld);
    
    const auto confidence = confidenceTexture.sample(colorSampler, texCoord).r;

    if (position.x*position.x + position.z*position.z < RADIUS*RADIUS
        && confidence == 2
        ) {
        auto i = int(position.x/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
        auto j = int(position.z/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
        device auto& md = myMeshData[i*GRID_NODE_COUNT + j];
        
        const auto val = position.y;
        device auto& len = md.length;
        auto pos = find_greater(val, md.heights, len);
        if (pos < MAX_MESH_STATISTIC && len < MAX_MESH_STATISTIC) {
            shift_right(pos, md.heights, len);
            md.heights[pos] = val;
            if (len != MAX_MESH_STATISTIC) {
                ++len;
            }
        }
    }
}




//vertex RGBVertexOut rgbVertex(uint vertexID [[vertex_id]],
//                              constant RGBUniforms &uniforms [[buffer(0)]]) {
//    const float3 texCoord = float3(viewTexCoords[vertexID], 1) * uniforms.viewToCamera;
//
//    RGBVertexOut out;
//    out.position = float4(viewVertices[vertexID], 0, 1);
//    out.texCoord = texCoord.xy;
//
//    return out;
//}
//
//fragment float4 rgbFragment(RGBVertexOut in [[stage_in]],
//                            constant RGBUniforms &uniforms [[buffer(0)]],
//                            texture2d<float, access::sample> capturedImageTextureY [[texture(kTextureY)]],
//                            texture2d<float, access::sample> capturedImageTextureCbCr [[texture(kTextureCbCr)]]) {
//
//    const float2 offset = (in.texCoord - 0.5) * float2(1, 1 / uniforms.viewRatio) * 2;
//    const float visibility = saturate(uniforms.radius * uniforms.radius - length_squared(offset));
//    const float4 ycbcr = float4(capturedImageTextureY.sample(colorSampler, in.texCoord.xy).r, capturedImageTextureCbCr.sample(colorSampler, in.texCoord.xy).rg, 1);
//
//    // convert and save the color back to the buffer
//    const float3 sampledColor = (yCbCrToRGB * ycbcr).rgb;
//    return float4(sampledColor, 1) * visibility;
//}




//vertex ParticleVertexOut particleVertex(uint vertexID [[vertex_id]],
//                                        constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
//                                        constant ParticleUniforms *particleUniforms [[buffer(kParticleUniforms)]]) {
//
//    // get point data
//    const auto particleData = particleUniforms[vertexID];
//    const auto position = particleData.position;
//    const auto confidence = particleData.confidence;
//    const auto sampledColor = particleData.color;
//    const auto visibility = confidence >= uniforms.confidenceThreshold;
//
//    // animate and project the point
//    float4 projectedPosition = uniforms.viewProjectionMatrix * float4(position, 1.0);
//    const float pointSize = max(uniforms.particleSize / max(1.0, projectedPosition.z), 2.0);
//    projectedPosition /= projectedPosition.w;
//
//    // prepare for output
//    ParticleVertexOut out;
//    out.position = projectedPosition;
//    out.pointSize = pointSize;
//    out.color = float4(sampledColor, visibility);
//
//    return out;
//}




//fragment float4 particleFragment(ParticleVertexOut in [[stage_in]],
//                                 const float2 coords [[point_coord]]) {
//    // we draw within a circle
//    const float distSquared = length_squared(coords - float2(0.5));
//    if (in.color.a == 0 || distSquared > 0.25) {
//        discard_fragment();
//    }
//
//    return in.color;
//}





vertex ParticleVertexOut gridVertex( constant MyMeshData* myMeshData [[ buffer(kMyMesh) ]],
                          constant PointCloudUniforms &uniforms [[ buffer(kPointCloudUniforms) ]],
                         unsigned int vid [[ vertex_id ]] )
{
    constant auto &md = myMeshData[vid];

//    const auto x = gridXCoord(vid);
//    const auto z = gridZCoord(vid);
//    const auto y = getMedian(md);
    const auto x = (vid/GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
    const auto z = (vid%GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
    const auto y = md.heights[md.length/2];

    float4 projectedPosition = uniforms.viewProjectionMatrix * float4(x, y, z, 1);
    projectedPosition /= projectedPosition.w;
    
    ParticleVertexOut pOut;
    pOut.position = projectedPosition;
    pOut.pointSize = 5;
    float4 color(1, 1, 1, 0.85);
    if (md.group == Group::Unknown) {
        color.a = 0.0;
    } else if (md.group == Group::Floor) {
        color.r = 0.5;
        color.g = 0;
        color.b = 0.5;
    } else {
        color.r = 0.1;
        color.g = 0.3;
        color.b = 0.1;
    }
    
    pOut.color = color;
    return pOut;
}

fragment float4 gridFragment(ParticleVertexOut in[[stage_in]])
{
    return in.color;
}

