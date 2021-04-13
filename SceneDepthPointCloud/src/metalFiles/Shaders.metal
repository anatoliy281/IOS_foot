#include <metal_stdlib>
#include <simd/simd.h>
#import "../ShaderTypes.h"
#include "../MyMeshData.h"
#include <metal_array>

using namespace metal;

//// Particle vertex shader outputs and fragment shader inputs
struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]] = POINT_SIZE;
    float4 color;
};


float4x4 shiftCoords(float h) {
    return float4x4( float4( 1, 0, 0, 0),
                     float4( 0, 0, 1, 0),
                     float4( 0, 1, 0, 0),
                     float4( 0, 0, -h, 1)
                    );
}

float4x4 shiftCoordsBack(float h) {
    return float4x4( float4( 1, 0, 0, 0),
                     float4( 0, 0, 1, 0),
                     float4( 0, 1, 0, 0),
                     float4( 0, h, 0, 1)
                    );
}

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
    i = round(position.x/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
    j = round(position.z/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
    value = position.y;
}

void mapToSphericalTable(float floorHeight, float4 position, thread int& i, thread int& j, thread float& value) {
    
    const auto spos = shiftCoords(floorHeight)*position;
    
    auto theta = atan2( length( float2(spos.xy) ), spos.z );
    auto phi = atan( spos.y / spos.x );
    if ( spos.x < 0 ) {
        phi += PI;
    } else if ( spos.y < 0 && spos.x > 0) {
        phi += 2*PI;
    } else {}
    
//    if (abs(theta - PI/2) < 50*PI/180) {
//        i = j = -1;
//    }
    
    i = round( theta / THETA_STEP );
    j = round( phi / PHI_STEP );
    value = length( float3(spos.xyz) );
}

float4 restoreFromCartesianTable(constant MyMeshData& md, int index) {
    float4 pos(1);
    pos.x = (index/GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
    pos.z = (index%GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
    pos.y = getValue(md);
    
    return pos;
}

float4 restoreFromSphericalTable(float floorHeight, constant MyMeshData& md, int index) {
    const auto theta = (index/GRID_NODE_COUNT)*THETA_STEP;
    const auto phi = (index%GRID_NODE_COUNT)*PHI_STEP;
    const auto rho = getValue(md);
    
    float4 pos(1);
    pos.x = rho*sin(theta)*cos(phi);
    pos.y = rho*sin(theta)*sin(phi);
    pos.z = rho*cos(theta);

    return shiftCoordsBack(floorHeight)*pos;
}

float4 colorCartesianPoint(constant MyMeshData& md) {
    float4 color(0.1, 0.3, 0.1, 0);
    color.a = static_cast<float>(md.length) / MAX_MESH_STATISTIC;
    return color;
}

float4 colorSphericalPoint(float floorDist, constant MyMeshData& md) {
    const float4 childUnexpected(247/255, 242/255, 26/255, 0);
    const float4 scarlet(1, 36/255, 0, 0);
    float gradient = getValue(md) / RADIUS;
    float4 footColor = mix(childUnexpected, scarlet, gradient);
    
    float floorGrad = 1;
    if ( floorDist < MAX_GRAD_H ) {
        floorGrad = floorDist / MAX_GRAD_H;
    }
    
    const float4 green(0.1, 0.3, 0.1, 0);
    float4 color = mix(green, footColor, floorGrad);
    color.a = static_cast<float>(md.length) / MAX_MESH_STATISTIC;
    return color;
}

float4 projectOnScreen(constant PointCloudUniforms &uniforms, const thread float4& pos) {
    float4 res = uniforms.viewProjectionMatrix * pos;
    res /= res.w;
    return res;
}

///  Vertex shader that takes in a 2D grid-point and infers its 3D position in world-space, along with RGB and confidence
vertex void unprojectVertex(uint vertexID [[vertex_id]],
                            constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
                            constant float2 *gridPoints [[ buffer(kGridPoints) ]],
                            constant float& floorHeight[[ buffer(kHeight) ]],
                            device MyMeshData *myMeshData[[ buffer(kMyMesh) ]],
                            texture2d<float, access::sample> depthTexture [[texture(kTextureDepth)]],
                            texture2d<unsigned int, access::sample> confidenceTexture [[texture(kTextureConfidence)]]
                            ) {
    
    const auto gridPoint = gridPoints[vertexID];

    const auto texCoord = gridPoint / uniforms.cameraResolution;
    // Sample the depth map to get the depth value
    const auto depth = depthTexture.sample(colorSampler, texCoord).r;
    
    if (depth < 0.3) {
        return;
    }
    
    // With a 2D point plus depth, we can now get its 3D position
    const auto position = worldPoint(gridPoint, depth, uniforms.cameraIntrinsicsInversed, uniforms.localToWorld);
    
    const auto confidence = confidenceTexture.sample(colorSampler, texCoord).r;

    if (
        position.x*position.x + position.z*position.z < RADIUS*RADIUS
        &&
        confidence > 0
        ) {
        
        int i, j;
        float val;
        if (floorHeight == -10) {
            mapToCartesianTable(position, i, j, val);
        } else {
            mapToSphericalTable(floorHeight, position, i, j, val);
        }
        if ( i < 0 || j < 0 || i > GRID_NODE_COUNT-1 || j > GRID_NODE_COUNT-1 ) {
            return ;
        }
        
        device auto& md = myMeshData[i*GRID_NODE_COUNT + j];
        device auto& len = md.length;
        auto pos = find_greater(val, md.heights, len);
        if (pos < MAX_MESH_STATISTIC && len < MAX_MESH_STATISTIC) {
            shift_right(pos, md.heights, len);
            md.heights[pos] = val;
            ++len;
        }
            
        if (floorHeight != 0) {
            auto h = md.heights[md.length/2];
            const auto heightDeviation = abs(h - floorHeight);
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
                                     constant float& floorHeight[[ buffer(kHeight) ]],
                                     unsigned int vid [[ vertex_id ]] )
{
    constant auto &md = myMeshData[vid];

    float4 pos, color;
    if (floorHeight == 0) {
        pos = restoreFromCartesianTable(md, vid);
        color = colorCartesianPoint(md);
    } else {
        pos = restoreFromSphericalTable(floorHeight, md, vid);
        color = colorSphericalPoint(abs(pos.y - floorHeight), md);
    }
    
    ParticleVertexOut pOut;
    pOut.position = projectOnScreen(uniforms, pos);
    pOut.color = color;
    return pOut;
}

fragment float4 gridFragment(ParticleVertexOut in[[stage_in]])
{
    return in.color;
}

