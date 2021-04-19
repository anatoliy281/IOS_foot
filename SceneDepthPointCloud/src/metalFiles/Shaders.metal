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

float getMedianValue(constant MyMeshData& md) {
    return md.heights[md.length/2];
}

float getPosValue(constant MyMeshData& md, constant int& pos) {
    return md.heights[pos-1];
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
    
    i = round( theta / THETA_STEP );
    j = round( phi / PHI_STEP );
//    value = (abs(theta - PI/2) > (3*PI/180))? length( float3(spos.xyz) ): 0;
    const auto l = length( float3(spos.xyz) );
    
//    const float kA = 1500;
//    const float kB = 1000;
//    const float lA = 0.36;
//    const float lB = 0.04;
//    const auto alpha = ( kA*(l - lB)/(lA - lB) + kB*(l - lA)/(lB - lA) )*l;
//    const auto eps = 0.0005;
//    const auto x = theta - M_PI_2_F + log( (1-eps)/eps ) / alpha;
    float sigma = 1;// / ( exp(alpha*x) + 1 );
    
    value = sigma*l;
}

float4 restoreFromCartesianTable(float h, int index) {
    float4 pos(1);
    pos.x = (index/GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
    pos.z = (index%GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
    pos.y = h;
    
    return pos;
}

float4 restoreFromSphericalTable(float floorHeight, float rho, int index) {
    const auto theta = (index/GRID_NODE_COUNT)*THETA_STEP;
    const auto phi = (index%GRID_NODE_COUNT)*PHI_STEP;
    
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

float4 colorSphericalPoint(float floorDist, float rho, constant int& state) {
    const float4 childUnexpected(247/255, 242/255, 26/255, 0);
    const float4 yellow(1, 211/255, 0, 0);
    float gradient = rho / RADIUS;
    float4 footColor = mix(childUnexpected, yellow, gradient);
    
    float floorGrad = 1;
    if ( floorDist < MAX_GRAD_H ) {
        floorGrad = floorDist / MAX_GRAD_H;
    }
    
    const float4 green(0.1, 0.3, 0.1, 0);
    float4 color = mix(green, footColor, floorGrad);
    float saturation = 1;
//    if (state == 2) {
//        saturation = 1;
//    } else {
//        saturation = static_cast<float>(md.length) / MAX_MESH_STATISTIC;
//    }
    color.a = saturation;

    return color;
}

float4 projectOnScreen(constant PointCloudUniforms &uniforms, const thread float4& pos) {
    float4 res = uniforms.viewProjectionMatrix * pos;
    res /= res.w;
    return res;
}

void populateOrderd( device MyMeshData& md, float value ) {
    device auto& len = md.length;
    if (len >= MAX_MESH_STATISTIC) {
        return;
    }
    auto pos = find_greater(value, md.heights, len);
    if ( pos < MAX_MESH_STATISTIC ) {
        shift_right(pos, md.heights, len);
        md.heights[pos] = value;
        ++len;
    }
}

void populateUnorderd( device MyMeshData& md, float value, constant int& frame) {
    if (frame >= MAX_MESH_STATISTIC) {
        return;
    }
    md.heights[frame] = value;
}

void markCartesianMeshNodes(device MyMeshData& md, constant float& floorHeight) {
    auto h = md.heights[md.length/2];
    auto heightDeviation = abs(h - floorHeight);
    if ( heightDeviation < 2*EPS_H ) {
        md.group = Floor;
    } else {
        md.group = Foot;
    }
}

void markSphericalMeshNodes(device MyMeshData& md, int thetaIndex) {
    
    auto h = md.heights[md.length/2];
    auto heightDeviation = abs(h*cos(thetaIndex*THETA_STEP));
    if ( heightDeviation < 2*EPS_H ) {
        md.group = Floor;
    } else {
        md.group = Foot;
    }
}

///  Vertex shader that takes in a 2D grid-point and infers its 3D position in world-space, along with RGB and confidence
vertex void unprojectVertex(uint vertexID [[vertex_id]],
                            
                            constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
                            constant float2 *gridPoints [[ buffer(kGridPoints) ]],
                            constant int& state [[ buffer(kStateNum) ]],
                            constant float& floorHeight[[ buffer(kHeight) ]],
                            constant int& frame [[ buffer(kFrame) ]],
                            device MyMeshData *myMeshData[[ buffer(kMyMesh) ]],
                            
                            texture2d<float, access::sample> depthTexture [[texture(kTextureDepth)]],
                            texture2d<unsigned int, access::sample> confidenceTexture [[texture(kTextureConfidence)]]
                            ) {
    const auto gridPoint = gridPoints[vertexID];

    const auto texCoord = gridPoint / uniforms.cameraResolution;
    // Sample the depth map to get the depth value
    const auto depth = depthTexture.sample(colorSampler, texCoord).r;
    
    if (depth < 0.15 ) {
        return;
    }
    
    // With a 2D point plus depth, we can now get its 3D position
    const auto position = worldPoint(gridPoint, depth, uniforms.cameraIntrinsicsInversed, uniforms.localToWorld);
    
    const auto confidence = confidenceTexture.sample(colorSampler, texCoord).r;

    bool check1 = position.x*position.x + position.z*position.z < RADIUS*RADIUS;
    
    if (
        check1
        &&
        confidence > 1
        ) {
        
        int i, j;
        float val;
        if (floorHeight == -10) { // TODO  узкое место (переделать на проверку state)
            mapToCartesianTable(position, i, j, val);
        } else {
            mapToSphericalTable(floorHeight, position, i, j, val);
        }
        if ( i < 0 || j < 0 || i > GRID_NODE_COUNT-1 || j > GRID_NODE_COUNT-1 ) {
            return ;
        }
        
        device auto& md = myMeshData[i*GRID_NODE_COUNT + j];
        if (state == 2) {
            populateUnorderd(md, val, frame);
        } else {
            populateOrderd(md, val);
        }
        
        if (state == 0) {
            markCartesianMeshNodes(md, floorHeight);
        } else  {
            markSphericalMeshNodes(md, i);
        }
    }
}


vertex ParticleVertexOut gridVertex( constant MyMeshData* myMeshData [[ buffer(kMyMesh) ]],
                                     constant PointCloudUniforms &uniforms [[ buffer(kPointCloudUniforms) ]],
                                     constant float& floorHeight [[ buffer(kHeight) ]],
                                     constant int& frame [[ buffer(kFrame) ]],
                                     constant int& state [[ buffer(kStateNum) ]],
                                     unsigned int vid [[ vertex_id ]] )
{
    constant auto &md = myMeshData[vid];

    const auto nodeVal = (state == 2)? getPosValue(md, frame): getMedianValue(md);
    float4 pos, color;
    if (state == 0) {
        pos = restoreFromCartesianTable(nodeVal, vid);
        color = colorCartesianPoint(md);
    } else { // state == 1 || state == 2
        pos = restoreFromSphericalTable(floorHeight, nodeVal, vid);
        color = colorSphericalPoint(abs(pos.y - floorHeight), nodeVal, state);
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

