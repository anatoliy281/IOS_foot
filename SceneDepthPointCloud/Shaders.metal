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

float getValue(constant MyMeshData& md) {
    return md.heights[md.length/2];
}


void mapToCartesianTable(float4 position, thread int& i, thread int& j, thread float& value) {
    i = int(position.x/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
    j = int(position.z/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
    value = position.y;
}

void mapToSphericalTable(float floorHeight, float4 position, thread int& i, thread int& j, thread float& value) {
    
    const auto x = position.x;
    const auto y = position.z;
    const auto z = position.y - floorHeight;
    
    const auto rho = float2(x, y);
    auto theta = atan2( length(rho), z );
    auto phi = atan( y / x );
    
//    if (y > 0 && x < 0) {
//        phi += PI;
//    }
    if ( x < 0 ) {
        phi += PI;
    }
    else if (y < 0 && x > 0) {
        phi += 2*PI;
    }
//    else if ( y < 0 && x < 0) {
//        phi += PI;
//    }
    else {}
    i = int( theta / THETA_STEP );
    j = int( phi / PHI_STEP );
    const auto r = float3(x, y, z);
    value = length(r);
}

float4 restoreFromCartesianTable(constant MyMeshData& md, int index) {
    float4 pos;
    pos.x = (index/GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
    pos.z = (index%GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
    pos.y = md.heights[md.length/2];
    pos.w = 1;
    
    return pos;
}

float4 restoreFromSphericalTable(float floorHeight, constant MyMeshData& md, int index) {
    const auto theta = (index/GRID_NODE_COUNT)*THETA_STEP;
    const auto phi = (index%GRID_NODE_COUNT)*PHI_STEP;
    const auto rho = getValue(md);
    
    const auto x = rho*sin(theta)*cos(phi);
    const auto y = rho*sin(theta)*sin(phi);
    const auto z = rho*cos(theta);

    return float4(x, z + floorHeight, y, 1);
}

float4 colorCartesianPoint(constant MyMeshData& md) {
    const float4 purple(0.5, 0, 0.5, 0);
    const float4 green(0.1, 0.3, 0.1, 0);
    float4 color = purple + (green - purple)*md.gradient;
    color.a = static_cast<float>(md.length) / MAX_MESH_STATISTIC;
    return color;
}

float4 colorSphericalpoint(float floorDist, constant MyMeshData& md) {
    const float4 childUnexpected(247/255, 242/255, 26/255, 1);
    const float4 scarlet(1, 36/255, 0, 1);
    float gradient = getValue(md) / RADIUS;
    float4 footColor = childUnexpected + (scarlet - childUnexpected)*gradient;
    footColor.a = static_cast<float>(md.length) / MAX_MESH_STATISTIC;
    
    float floorGrad;
    if ( floorDist > MAX_GRAD_H ) {
        floorGrad = 1;
    } else {
        floorGrad = floorDist / MAX_GRAD_H;
    }
    
    const float4 green(0.1, 0.3, 0.1, 0);
    return green + (footColor - green)*floorGrad;
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

    if (
        position.x*position.x + position.z*position.z < RADIUS*RADIUS
        &&
        confidence == 2
        ) {
        
        int i, j;
        float val;
        if (heights.floor == 0) {
            mapToCartesianTable(position, i, j, val);
        } else {
            mapToSphericalTable(heights.floor, position, i, j, val);
            if ( i < 0 || j < 0 || i > GRID_NODE_COUNT-1 || j > GRID_NODE_COUNT-1 ) {
                return ;
            }
        }
        
        
        device auto& md = myMeshData[i*GRID_NODE_COUNT + j];
        device auto& len = md.length;
        auto pos = find_greater(val, md.heights, len);
        if (pos < MAX_MESH_STATISTIC && len < MAX_MESH_STATISTIC) {
            shift_right(pos, md.heights, len);
            md.heights[pos] = val;
            ++len;
        }
            
        if (heights.floor == 0) {
            auto h = md.heights[md.length/2];
            const auto heightDeviation = abs(h - heights.floor);
//            if ( heightDeviation > MAX_GRAD_H ) {
//                md.gradient = 1;
//            } else {
//                md.gradient = static_cast<float>(heightDeviation) / MAX_GRAD_H;
//            }
            if ( heightDeviation < EPS_H ) {
                md.group = Floor;
            } else {
                md.group = Foot;
            }
        }
    }
}


vertex ParticleVertexOut gridVertex( constant MyMeshData* myMeshData [[ buffer(kMyMesh) ]],
                                     constant PointCloudUniforms &uniforms [[ buffer(kPointCloudUniforms) ]],
                                     constant Heights& heights[[ buffer(kHeight) ]],
                                     unsigned int vid [[ vertex_id ]] )
{
    constant auto &md = myMeshData[vid];

    float4 pos, color;
    if (heights.floor == 0) {
        pos = restoreFromCartesianTable(md, vid);
        color = colorCartesianPoint(md);
    } else {
        pos = restoreFromSphericalTable(heights.floor, md, vid);
//        pos = restoreFromSphericalTable(0, md, vid);
        color = colorSphericalpoint(abs(pos.y - heights.floor), md);
    }

    float4 projectedPosition = uniforms.viewProjectionMatrix * pos;
    projectedPosition /= projectedPosition.w;
    
    ParticleVertexOut pOut;
    pOut.position = projectedPosition;
  
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
