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

//// Particle vertex shader outputs and fragment shader inputs
struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]] = 12;
    float4 color;
};
//
constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);

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


int new_cicle(device float* ar, float medianValue) {
    
    auto halflen = MAX_MESH_STATISTIC/2;
    for (int i=0; i < halflen; ++i) {
        ar[i] = medianValue;
    }
    
    return halflen;
}


///  Vertex shader that takes in a 2D grid-point and infers its 3D position in world-space, along with RGB and confidence
vertex void unprojectVertex(uint vertexID [[vertex_id]],
                            constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
                            constant float2 *gridPoints [[ buffer(kGridPoints) ]],
                            constant Heights& heights[[ buffer(kHeight) ]],
                            device MyMeshData *myMeshData[[ buffer(kMyMesh) ]],
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
        
        const auto maxHeight = heights.floor + heights.delta;
        const auto val = min(position.y, maxHeight);
        
        device auto& len = md.length;
        auto pos = find_greater(val, md.heights, len);
        if (pos < MAX_MESH_STATISTIC && len < MAX_MESH_STATISTIC) {
            shift_right(pos, md.heights, len);
            md.heights[pos] = val;
            ++len;
        }
//        if (len == MAX_MESH_STATISTIC) {
////            md.heights[0] = md.heights[md.length/2];
////            len = 1;
//            auto median = md.heights[md.length/2];
//            len = new_cicle(md.heights, median);
//        }
        
        auto h = md.heights[md.length/2];
        if ( abs(h - heights.floor) < 3e-3 ) {
            md.group = Floor;
        } else {
            md.group = Foot;
        }
    }
}


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
//    pOut.pointSize = 25;
    float4 color(1, 1, 1, 0.85);
    if (md.group == Group::Unknown) {
//        color.a = 0.0;
    } else if (md.group == Group::Floor) {
        color.r = 0.5;
        color.g = 0;
        color.b = 0.5;
    } else {
        color.r = 0.1;
        color.g = 0.3;
        color.b = 0.1;
    }
    color.a = static_cast<float>(md.length) / MAX_MESH_STATISTIC;
    
    pOut.color = color;
    return pOut;
}

fragment float4 gridFragment(ParticleVertexOut in[[stage_in]])
{
    return in.color;
}

