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


bool mapToMeshData(const thread float4& posCoord,
                   constant ProjectionView& view,
                   constant Heights& height,
                   thread int& i, thread int& j, thread int& columnCount, thread float& value) {
    if ( view == Front || view == Back ) {
        i = int(posCoord.x/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
        j = int((posCoord.y - height.floor)/GRID_NODE_DISTANCE);
        if ( j < 0 || j > GRID_NODE_COUNT/2 - 1)
            return false;
        value = posCoord.z;
        columnCount = GRID_NODE_COUNT / 2;
    } else if ( view == Left || view == Right ) {
        i = int((posCoord.y - height.floor)/GRID_NODE_DISTANCE);
        if ( i < 0 || i > GRID_NODE_COUNT/2 - 1)
            return false;
        j = int(posCoord.z/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
        value = posCoord.x;
        columnCount = GRID_NODE_COUNT;
    } else {
        i = int(posCoord.x/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
        j = int(posCoord.z/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
        value = posCoord.y;
        columnCount = GRID_NODE_COUNT;
    }
    return true;
}

float4 restoreCoord(constant MyMeshData* myMeshData,
                    unsigned int vid,
                    constant Heights& height,
                    constant ProjectionView& view ) {
    constant auto& md = myMeshData[vid];
    float4 res;
    if (view == Back || view == Front) {
        res.x = (vid/(GRID_NODE_COUNT/2))*GRID_NODE_DISTANCE - RADIUS;
        res.y = (vid%(GRID_NODE_COUNT/2))*GRID_NODE_DISTANCE + height.floor;
        res.z = md.heights[md.length/2];
    } else if (view == Right || view == Left) {
        res.x = md.heights[md.length/2];
        res.y = (vid/GRID_NODE_COUNT)*GRID_NODE_DISTANCE + height.floor;
        res.z = (vid%GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
    } else {
        res.x = (vid/GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
        res.y = md.heights[md.length/2];
        res.z = (vid%GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
    }
    res.w = 1;
    return res;
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
        int i, j, columnCount;
        float value;
        if (!mapToMeshData(position, projectionView, heights, i, j, columnCount, value))
            return;
        
        device auto& md = myMeshData[i*columnCount + j];
        
        device auto& len = md.length;
        auto pos = find_greater(value, md.heights, len);
        if (pos < MAX_MESH_STATISTIC && len < MAX_MESH_STATISTIC) {
            shift_right(pos, md.heights, len);
            md.heights[pos] = value;
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

float4 colorMesh(constant ProjectionView& view) {
    if ( view == Left ) {
        return float4(0.7, 0.1, 0.1, 0);
    } else if ( view == Right) {
        return float4(0.7, 0.1, 0.1, 0);
    } else if ( view == Back ) {
        return float4(0.3, 0.1, 0.1, 0);
    } else if ( view == Front) {
        return float4(0.1, 0.1, 0.3, 0);
    } else {
        return float4(0.1, 0.3, 0.1, 0);
    }
}

vertex ParticleVertexOut gridVertex( constant MyMeshData* myMeshData [[ buffer(kMyMesh) ]],
                                     constant ProjectionView& projectionView [[ buffer(kViewSide) ]],
                                     constant Heights& heights[[ buffer(kHeight) ]],
                                     constant PointCloudUniforms &uniforms [[ buffer(kPointCloudUniforms) ]],
                                     unsigned int vid [[ vertex_id ]] )
{
    const auto footColor = colorMesh(projectionView);
    const auto floorColor = float4(0.5, 0, 0.5, 0);
    
    auto globPos = restoreCoord(myMeshData, vid, heights, projectionView);
    
    float4 projectedPosition = uniforms.viewProjectionMatrix * globPos;
    projectedPosition /= projectedPosition.w;
    
    constant auto &md = myMeshData[vid];
    
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
