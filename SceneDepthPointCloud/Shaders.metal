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
    float pointSize [[point_size]] = POINT_SIZE;
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
                            constant ProjectionView& projectionView [[ buffer(kViewSide) ]],
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

    if (
        position.x*position.x + position.z*position.z < RADIUS*RADIUS
        &&
        confidence == 2
        ) {
        int i, j;
        int colCnt;
        float val;
        switch (projectionView) {
        case Up: {
            i = int(position.x/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
            j = int(position.z/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
            val = position.y;
            colCnt = GRID_NODE_COUNT;
            break;
        }
        case Back:
        case Front: {
            i = int(position.x/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
            j = int((position.y - heights.floor)/GRID_NODE_DISTANCE);
            if ( j < 0 || j > GRID_NODE_COUNT/2 - 1)
                return;
            val = position.z;
            colCnt = GRID_NODE_COUNT / 2;
            break;
        }
//        case Back: {
//            i = int(position.x/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
//            j = -int((position.y - heights.floor)/GRID_NODE_DISTANCE) + GRID_NODE_COUNT / 2;
//            val = position.z;
//            colCnt = GRID_NODE_COUNT / 2;
//            break;
//        }
//        case Left: {
//            i = -int((position.y - heights.floor)/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2 - 1;
//            if ( i < 0 || i > GRID_NODE_COUNT/2 - 1)
//                return;
//            j = int(position.z/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
//            val = position.x;
//            colCnt = GRID_NODE_COUNT;
//            break;
//        }
        case Left:
        case Right: {
            i = int((position.y - heights.floor)/GRID_NODE_DISTANCE);
            if ( i < 0 || i > GRID_NODE_COUNT/2 - 1)
                return;
            j = int(position.z/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
            val = position.x;
            colCnt = GRID_NODE_COUNT;
            break;
        }
        default : {
            return;
        }
        }
        
        device auto& md = myMeshData[i*colCnt + j];
        
////        const auto maxHeight = heights.floor + heights.delta;
////        const auto val = min(position.y, maxHeight);
        device auto& len = md.length;
        auto pos = find_greater(val, md.heights, len);
        if (pos < MAX_MESH_STATISTIC && len < MAX_MESH_STATISTIC) {
            shift_right(pos, md.heights, len);
            md.heights[pos] = val;
            ++len;
        }
        
        auto h = md.heights[md.length/2];
        const auto heightDeviation = abs(h - heights.floor);
        if ( heightDeviation > MAX_GRAD_H ) {
            md.gradient = 1;
        } else {
            md.gradient = static_cast<float>(heightDeviation) / MAX_GRAD_H;
        }
        if ( heightDeviation < EPS_H ) {
            md.group = Floor;
        } else {
            md.group = Foot;
        }
    }
}


vertex ParticleVertexOut gridVertex( constant MyMeshData* myMeshData [[ buffer(kMyMesh) ]],
                                     constant ProjectionView& projectionView [[ buffer(kViewSide) ]],
                                     constant Heights& heights[[ buffer(kHeight) ]],
                                     constant PointCloudUniforms &uniforms [[ buffer(kPointCloudUniforms) ]],
                                     unsigned int vid [[ vertex_id ]] )
{
    constant auto &md = myMeshData[vid];
    
    float4 footColor;
    const float4 floorColor(0.5, 0, 0.5, 0);
    
    float x, y, z;
    if (projectionView == Up) {
        footColor = float4(0.1, 0.3, 0.1, 0);
        x = (vid/GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
        y = md.heights[md.length/2];
        z = (vid%GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
    } else if (projectionView == Back || Front) {
        x = (vid/(GRID_NODE_COUNT/2))*GRID_NODE_DISTANCE - RADIUS;
        y = (vid%(GRID_NODE_COUNT/2))*GRID_NODE_DISTANCE + heights.floor;
        z = md.heights[md.length/2];
        if (projectionView == Back)
            footColor = float4(0.3, 0.1, 0.1, 0);
        else
            footColor = float4(0.1, 0.1, 0.3, 0);
    }
//    case Back: {
//        x = (vid/(GRID_NODE_COUNT/2))*GRID_NODE_DISTANCE - RADIUS;
//        y = -(vid%(GRID_NODE_COUNT/2))*GRID_NODE_DISTANCE + heights.floor + RADIUS;
//        z = md.heights[md.length/2];
//        break;
//    }
//    case Left: {
//        x = md.heights[md.length/2];
//        y = -(vid/GRID_NODE_COUNT)*GRID_NODE_DISTANCE + heights.floor + RADIUS;
//        z = (vid%GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
//        break;
//    }
    else if (projectionView == Right || Left) {
        x = md.heights[md.length/2];
        y = (vid/GRID_NODE_COUNT)*GRID_NODE_DISTANCE + heights.floor;
        z = (vid%GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
        if (projectionView == Right)
            footColor = float4(0.7, 0.1, 0.1, 0);
        else
            footColor = float4(0.1, 0.1, 0.7, 0);
    } else {
        x = y = z = 0;
        footColor = float4(0);
    }
    

    float4 projectedPosition = uniforms.viewProjectionMatrix * float4(x, y, z, 1);
    projectedPosition /= projectedPosition.w;
    
    ParticleVertexOut pOut;
    pOut.position = projectedPosition;
    float4 color = floorColor + (footColor - floorColor)*md.gradient;
    color.a = static_cast<float>(md.length) / MAX_MESH_STATISTIC;
    
    pOut.color = color;
    return pOut;
}

fragment float4 gridFragment(ParticleVertexOut in[[stage_in]])
{
    return in.color;
}

struct RGBVertexOut {
    float4 position [[position]];
    float2 texCoord;
};




constant auto yCbCrToRGB = float4x4(
                                    float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
                                    float4(+0.0000f, -0.3441f,  1.7720f, +0.0000f),
                                    float4( 1.4020f, -0.7141f, +0.0000f, +0.0000f),
                                    float4(-0.7010f,  0.5291f, -0.8860f, +1.0000f)
                                    );

vertex RGBVertexOut cameraImageVertex( uint vid [[ vertex_id ]],
                                       constant CameraView* image [[ buffer(kViewCorner) ]],
                                       constant matrix_float3x3& viewToCamera[[ buffer(kViewToCam) ]]) {
    RGBVertexOut out;
    out.position = float4(image[vid].viewVertices, 0, 1);
    out.texCoord = ( float3(image[vid].viewTexCoords, 1)*viewToCamera ).xy;
    return out;
}

fragment float4 cameraImageFragment(RGBVertexOut in [[stage_in]],
                                    texture2d<float, access::sample> capturedImageTextureY[[ texture(kTextureY) ]],
                                    texture2d<float, access::sample> capturedImageTextureCbCr[[ texture(kTextureCbCr) ]]
                                  ) {
    const auto uv = in.texCoord;
    const auto ycbcr = float4( capturedImageTextureY.sample(colorSampler, uv).r,
                               capturedImageTextureCbCr.sample(colorSampler, uv).rg, 1);
    
    return float4(float3(yCbCrToRGB*ycbcr).rgb, 1);
}





vertex ParticleVertexOut axisVertex( constant ColoredPoint* axis [[buffer(kVerteces)]],
                         constant PointCloudUniforms &uniforms [[ buffer(kPointCloudUniforms) ]],
                         unsigned int vid [[ vertex_id ]]
                         )
{
    ParticleVertexOut outPnt;
    outPnt.position = uniforms.viewProjectionMatrix * float4(axis[vid].position, 1);
    outPnt.color = ceil(float4(axis[vid].position, 1));
    return outPnt;
}

fragment float4 axisFragment(ParticleVertexOut in[[stage_in]])
{
    return in.color;
}
