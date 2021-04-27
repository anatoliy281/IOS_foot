#include <metal_stdlib>
#include <simd/simd.h>
#import "../ShaderTypes.h"
#include "../MyMeshData.h"
#include <metal_array>

using namespace metal;

constant float minDistance = 0.2;

// -------------------------- BASE DEFINITIONS -----------------------------

class MedianSearcher {
	device MyMeshData* md;
	constant MyMeshData* mdConst;
	
	void cycle();
	int incrementModulo(int x, int step = 1);
	float moveMedian(int greater);
	int detectShiftDirection(float median, float a, float b, bool add);
	
public:
	MedianSearcher(device MyMeshData* meshData): md(meshData), mdConst(nullptr) {}
	MedianSearcher(constant MyMeshData* meshData): md(nullptr), mdConst(meshData) {}
	void appendNewValue(float value);
	
	int getLength() const;
	
};



void MedianSearcher::cycle() {
	md->bufModLen = incrementModulo(md->bufModLen);
	md->totalSteps += 1;
}

int MedianSearcher::incrementModulo(int x, int step) {
	return (x + step + MAX_MESH_STATISTIC)%MAX_MESH_STATISTIC;
}

float MedianSearcher::moveMedian(int greater) {
	const auto med = md->median;
	auto newMed = med;
	
	bool firstCathed = false;
	
	if ( greater == 1 ) {	// стараемся найти ближайшую справа
		for (int i = 0; i < getLength(); ++i) {
			const auto deviation = md->buffer[i] - med;
			if ( deviation > 0 ) {
				if ( !firstCathed ) {
					newMed = md->buffer[i];
					firstCathed = true;
				} else if ( abs(deviation) < abs(newMed - med) ) {
					newMed = md->buffer[i];
				}
			}
		}
	} else if ( greater == -1 ) {	// стараемся найти ближайшую слева
		for (int i=0; i < getLength(); ++i) {
			const auto deviation = md->buffer[i] - med;
			if ( deviation < 0 ) {
				if ( !firstCathed ) {
					newMed = md->buffer[i];
					firstCathed = true;
				} else if ( abs(deviation) < abs(med - newMed)) {
					newMed = md->buffer[i];
				}
			}
		}
	} else {}

	return newMed;
}

int MedianSearcher::detectShiftDirection(float median, float a, float b, bool valuesAdded) {
	
	auto pairMin = min(a, b);
	auto pairMax = max(a, b);
	
	int res = 0;
	if ( median < pairMin ) { // сдвинуть медану на ближайшее значение вправо
		res = 1;
	} else if ( median > pairMax ) { // сдвинуться влево
		res = -1;
	}
	
	if (!valuesAdded)
		res = -1*res;
	
	return res;
}

void MedianSearcher::appendNewValue(float value) {
	
	md->lock = 1;

	device auto& med = md->median;
	if (md->totalSteps == 0) { // срабатывает один единственный раз
		md->buffer[md->bufModLen] = med = value;
		md->pairLen = 0;
		cycle();
		md->lock = 0;
		return;
	}

	device int& plen = md->pairLen;
	if (plen < 2)
		md->pairs[plen++] = value;
	if (plen == 2) { // пара готова
		int p1 = md->bufModLen;
		int p2 = incrementModulo(p1);
		
		// проверка на удаление текущей медианы
		if (md->buffer[p1] == med) {
			p1 = incrementModulo(p1, -1);
		}
		if (md->buffer[p2] == med) {
			p2 = incrementModulo(p2);
		}
		
		if (md->bufModLen < md->totalSteps ) {
			auto a_old = md->buffer[p1];
			auto b_old = md->buffer[p2];
			// пересчет медианы при удалении
			auto shiftToGreater = detectShiftDirection(med, a_old, b_old, false);
//			cycle();
//			cycle();
			med = moveMedian(shiftToGreater);

		}
		
		
		
		auto a = md->buffer[p1] = md->pairs[--plen];
		auto b = md->buffer[p2] = md->pairs[--plen];
		
		cycle();
		cycle();
		auto shiftToGreater = detectShiftDirection(med, a, b, true);

		med = moveMedian(shiftToGreater);
	}
	md->lock = 0;
}

int MedianSearcher::getLength() const {
	auto totalSteps = (mdConst)? mdConst->totalSteps: md->totalSteps;
	return min(totalSteps, MAX_MESH_STATISTIC);
}


//// Particle vertex shader outputs and fragment shader inputs
struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]] = POINT_SIZE;
    float4 color;
};

constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);

/// Retrieves the world position of a specified camera point with depth
static simd_float4 worldPoint(simd_float2 cameraPoint, float depth, matrix_float3x3 cameraIntrinsicsInversed, matrix_float4x4 localToWorld) {
    const auto localPoint = cameraIntrinsicsInversed * simd_float3(cameraPoint, 1) * depth;
    const auto worldPoint = localToWorld * simd_float4(localPoint, 1);
    
    return worldPoint / worldPoint.w;
}

float4 projectOnScreen(constant PointCloudUniforms &uniforms, const thread float4& pos) {
    float4 res = uniforms.viewProjectionMatrix * pos;
    res /= res.w;
    return res;
}
	


// ------------------------------------- CARTESIAN ------------------------------------



void mapToCartesianTable(float4 position, thread int& i, thread int& j, thread float& value) {
    i = round(position.x/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
    j = round(position.z/GRID_NODE_DISTANCE) + GRID_NODE_COUNT/2;
    value = position.y;
}

float4 restoreFromCartesianTable(float h, int index) {
    float4 pos(1);
    pos.x = (index/GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
    pos.z = (index%GRID_NODE_COUNT)*GRID_NODE_DISTANCE - RADIUS;
    pos.y = h;
    
    return pos;
}

//float4 colorCartesianPoint(constant MyMeshData& md) {
//    float4 color(0.1, 0.3, 0.1, 0);
//    color.a = static_cast<float>(MedianSearcher(&md).getLength()) / MAX_MESH_STATISTIC;
//    return color;
//}

void markCartesianMeshNodes(device MyMeshData& md, constant float& floorHeight) {
    auto h = md.median;
    auto heightDeviation = abs(h - floorHeight);
    if ( heightDeviation < 2*EPS_H ) {
        md.group = Floor;
    } else {
        md.group = Foot;
    }
}

vertex void unprojectCartesianVertex(
                            uint vid [[vertex_id]],
                            constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
                            constant float2 *gridPoints [[ buffer(kGridPoints) ]],
                            constant float& floorHeight[[ buffer(kHeight) ]],
                            device MyMeshData *myMeshData[[ buffer(kMyMesh) ]],
                            texture2d<float, access::sample> depthTexture [[texture(kTextureDepth)]],
                            texture2d<unsigned int, access::sample> confidenceTexture [[texture(kTextureConfidence)]]
                            ) {
    const auto gridPoint = gridPoints[vid];

    const auto texCoord = gridPoint / uniforms.cameraResolution;
    // Sample the depth map to get the depth value
    const auto depth = depthTexture.sample(colorSampler, texCoord).r;
    
    if (depth < minDistance ) {
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
        mapToCartesianTable(position, i, j, val);
        if ( i < 0 || j < 0 || i > GRID_NODE_COUNT-1 || j > GRID_NODE_COUNT-1 ) {
            return ;
        }
        
        device auto& md = myMeshData[i*GRID_NODE_COUNT + j];
		if (md.lock == 1)
			return;
		
		auto shr = MedianSearcher(&md);
		shr.appendNewValue(val);
		
        markCartesianMeshNodes(md, floorHeight);
    }
}



// ------------------------- BASE SPHERICAL -------------------------------



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

float4 restoreFromSphericalTable(float floorHeight, float rho, int index) {
    const auto theta = (index/GRID_NODE_COUNT)*THETA_STEP;
    const auto phi = (index%GRID_NODE_COUNT)*PHI_STEP;
    
    float4 pos(1);
    pos.x = rho*sin(theta)*cos(phi);
    pos.y = rho*sin(theta)*sin(phi);
    pos.z = rho*cos(theta);

    return shiftCoordsBack(floorHeight)*pos;
}

float4 colorSphericalPoint(float floorDist, float rho, float saturation) {
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
    color.a = saturation;

    return color;
}


void markSphericalMeshNodes(device MyMeshData& md, int thetaIndex) {
    
    auto h = md.median;
    auto heightDeviation = abs(h*cos(thetaIndex*THETA_STEP));
    if ( heightDeviation < 2*EPS_H ) {
        md.group = Floor;
    } else {
        md.group = Foot;
    }
}





// --------------------- SPHERICAL GRID ------------------------------------


float detectNodeOrientationToCamera(constant PointCloudUniforms &uniforms, const thread float4& nodePos, constant float& floorHeight) {
	constant auto& mat = uniforms.localToWorld;
	auto camOrigin = (mat*float4(0, 0, 0, 1)).xyz;
	auto camDir = normalize( (mat*float4(0, 0, 1, 1)).xyz - camOrigin );
	auto nodeDir = normalize( nodePos.xyz - float3(0, floorHeight, 0) );
	auto cosine = -dot(camDir, nodeDir);
	
	if (cosine < 0) {
		cosine = 0;
	}
	
	return cosine*cosine*cosine;
}


vertex void unprojectSphericalVertex(
                            uint vertexID [[vertex_id]],

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

    if (depth < minDistance ) {
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
        mapToSphericalTable(floorHeight, position, i, j, val);
        if ( i < 0 || j < 0 || i > GRID_NODE_COUNT-1 || j > GRID_NODE_COUNT-1 ) {
            return ;
        }

        device auto& md = myMeshData[i*GRID_NODE_COUNT + j];
		
		if (md.lock == 1)
			return;
		
		if ( detectNodeOrientationToCamera(uniforms, position, floorHeight) < 0.5 )
			return;
		
		
		MedianSearcher(&md).appendNewValue(val);
        markSphericalMeshNodes(md, i);
    }
}

float4 shineDirection(float4 inColor, float mixFactor) {
	return mix(inColor, float4(1, 1, 0, 1), mixFactor);
}

vertex ParticleVertexOut gridSphericalMeshVertex( constant MyMeshData* myMeshData [[ buffer(kMyMesh) ]],
                                     constant PointCloudUniforms &uniforms [[ buffer(kPointCloudUniforms) ]],
                                     constant float& floorHeight [[ buffer(kHeight) ]],
                                     unsigned int vid [[ vertex_id ]] ) {
    constant auto &md = myMeshData[vid];

    const auto nodeVal = md.median;
    auto pos = restoreFromSphericalTable(floorHeight, nodeVal, vid);
    auto saturation = static_cast<float>(MedianSearcher(&md).getLength()) / MAX_MESH_STATISTIC;
    
	float4 color = colorSphericalPoint(abs(pos.y - floorHeight), nodeVal, saturation);
	float mixFactor = detectNodeOrientationToCamera(uniforms, pos, floorHeight);
	float4 shined = shineDirection(color, mixFactor);
	
    ParticleVertexOut pOut;
    pOut.position = projectOnScreen(uniforms, pos);
	pOut.color = shined;
    return pOut;
}



// -------------------------------------- SINGLE FRAME (IN SPHERICAL COORDS) ---------------------------------------------



void populateUnorderd( device MyMeshData& md, float value, constant int& frame) {
    if (frame >= MAX_MESH_STATISTIC) {
        return;
    }
    md.buffer[frame] = value;
}

vertex void unprojectSingleFrameVertex(
                            uint vertexID [[vertex_id]],
                            constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
                            constant float2 *gridPoints [[ buffer(kGridPoints) ]],
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
    if ( !check1 || confidence < 2 ) {
        return;
        
    }
    int i, j;
    float val;
    mapToSphericalTable(floorHeight, position, i, j, val);
    if ( i < 0 || j < 0 || i > GRID_NODE_COUNT-1 || j > GRID_NODE_COUNT-1 ) {
        return ;
    }
    device auto& md = myMeshData[i*GRID_NODE_COUNT + j];
    populateUnorderd(md, val, frame);
    markSphericalMeshNodes(md, i);
}


vertex ParticleVertexOut singleFrameVertex(
                                        constant MyMeshData* myMeshData [[ buffer(kMyMesh) ]],
                                        constant PointCloudUniforms &uniforms [[ buffer(kPointCloudUniforms) ]],
                                        constant float& floorHeight [[ buffer(kHeight) ]],
                                        constant int& frame [[ buffer(kFrame) ]],
                                        unsigned int vid [[ vertex_id ]]
                                           ) {
    constant auto &md = myMeshData[vid];

    const auto nodeVal = md.buffer[frame-1];
    auto pos = restoreFromSphericalTable(floorHeight, nodeVal, vid);

    ParticleVertexOut pOut;
    pOut.position = projectOnScreen(uniforms, pos);
    pOut.color = colorSphericalPoint(abs(pos.y - floorHeight), nodeVal, 1);
    return pOut;
}



// --------------------------------- BASE FRAGMENT SHADER ------------------------------------------



fragment float4 gridFragment(ParticleVertexOut in[[stage_in]]) {
    return in.color;
}

