#include <metal_stdlib>
#include <simd/simd.h>
#import "../ShaderTypes.h"
#include "../MyMeshData.h"
#include <metal_array>

using namespace metal;

constant float minDistance = 0.25;
constant float idealDist = 0.3;
constant float acceptanceZone = 0.2;


constant float maxHeight = 0.2;
constant float maxHalfWidth = 0.08;
constant float backLength = 0.07;
constant float frontLength = 0.3;

constant float widthFloorZone = 0.03;

// -------------------------- BASE DEFINITIONS -----------------------------

class MedianSearcher {
	device MyMeshData* md;
	constant MyMeshData* mdConst;
	
	void cycle();
	int incrementModulo(int x, int step = 1);
//	float moveMedian(int greater);
//	int detectShiftDirection(float median, float a, float b, bool add);
	
public:
	MedianSearcher(device MyMeshData* meshData): md(meshData), mdConst(nullptr) {}
	MedianSearcher(constant MyMeshData* meshData): md(nullptr), mdConst(meshData) {}
	void newValue(float value);
	
//	int getLength() const;
	
};



void MedianSearcher::cycle() {
	md->bufModLen = incrementModulo(md->bufModLen);
	md->totalSteps += 1;
}

int MedianSearcher::incrementModulo(int x, int step) {
	return (x + step + MAX_MESH_STATISTIC)%MAX_MESH_STATISTIC;
}

//float MedianSearcher::moveMedian(int greater) {
//	const auto med = md->mean;
//	auto newMed = med;
//
//	bool firstCathed = false;
//
//	if ( greater == 1 ) {	// стараемся найти ближайшую справа
//		for (int i = 0; i < getLength(); ++i) {
//			const auto deviation = md->buffer[i] - med;
//			if ( deviation > 0 ) {
//				if ( !firstCathed ) {
//					newMed = md->buffer[i];
//					firstCathed = true;
//				} else if ( abs(deviation) < abs(newMed - med) ) {
//					newMed = md->buffer[i];
//				}
//			}
//		}
//	} else if ( greater == -1 ) {	// стараемся найти ближайшую слева
//		for (int i=0; i < getLength(); ++i) {
//			const auto deviation = md->buffer[i] - med;
//			if ( deviation < 0 ) {
//				if ( !firstCathed ) {
//					newMed = md->buffer[i];
//					firstCathed = true;
//				} else if ( abs(deviation) < abs(med - newMed)) {
//					newMed = md->buffer[i];
//				}
//			}
//		}
//	} else {}
//
//	return newMed;
//}
//
//int MedianSearcher::detectShiftDirection(float median, float a, float b, bool valuesAdded) {
//
//	auto pairMin = min(a, b);
//	auto pairMax = max(a, b);
//
//	int res = 0;
//	if ( median < pairMin ) { // сдвинуть медану на ближайшее значение вправо
//		res = 1;
//	} else if ( median > pairMax ) { // сдвинуться влево
//		res = -1;
//	}
//
//	if (!valuesAdded)
//		res = -1*res;
//
//	return res;
//}


void MedianSearcher::newValue(float value) {
	device auto& mean = md->mean;
	device auto& meanSquared = md->meanSquared;

	int n = md->bufModLen;
	md->buffer[n] = value;
	cycle();
	if ( md->bufModLen == md->totalSteps ) {
		mean = (mean*n + value) / (n + 1.f);
		meanSquared = (meanSquared*n + value*value) / (n + 1.f);
	} else if (md->bufModLen == 0) {
		float newMean = 0;
		float newMeanSquared = 0;
		for (int i = 0; i < MAX_MESH_STATISTIC; ++i) {
			newMean += md->buffer[i];
			newMeanSquared += md->buffer[i]*md->buffer[i];
		}
		newMean /= MAX_MESH_STATISTIC;
		newMeanSquared /= MAX_MESH_STATISTIC;
		auto dispersion = meanSquared - mean*mean;
		auto newDispersion = newMeanSquared - newMean*newMean;
		if (newDispersion < dispersion) {
			mean = newMean;
		}
	}

}


//int MedianSearcher::getLength() const {
//	auto totalSteps = (mdConst)? mdConst->totalSteps: md->totalSteps;
//	return min(totalSteps, MAX_MESH_STATISTIC);
//}


//// Particle vertex shader outputs and fragment shader inputs
struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]] = POINT_SIZE;
    float4 color;
};

constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);
//constexpr sampler depthSampler(mip_filter::none, mag_filter::nearest, min_filter::linear);
constexpr sampler depthSampler;

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
constant int gridNodeCount = GRID_NODE_COUNT;		// 500
constant float halfLength = RADIUS;					// 0.5
constant float gridNodeDist = 2*halfLength / gridNodeCount;
constant float gridNodeDistCylindricalZ = 0.5*gridNodeDist;


void mapToCartesianTable(float4 position, thread int& i, thread int& j, thread float& value) {
    i = round(position.x/gridNodeDist) + gridNodeCount/2;
    j = round(position.z/gridNodeDist) + gridNodeCount/2;
    value = position.y;
}

float4 restoreFromCartesianTable(float h, int index) {
    float4 pos(1);
    pos.x = (index/gridNodeCount)*gridNodeDist - halfLength;
    pos.z = (index%gridNodeCount)*gridNodeDist - halfLength;
    pos.y = h;
    
    return pos;
}

float4 colorCartesianPoint(float floorDist, float saturation) {
	float floorGrad = 1;
	if ( floorDist < MAX_GRAD_H ) {
		floorGrad = floorDist / MAX_GRAD_H;
	}
	
	const float4 green(0.1, 0.3, 0.1, 0);
	const float4 yellow(0.5, 0, 0, 0);
	float4 color = mix(green, yellow, floorGrad);
    color.a = saturation;
    return color;
}

void markCartesianMeshNodes(device MyMeshData& md, constant float& floorHeight) {
    auto h = md.mean;
    auto heightDeviation = abs(h - floorHeight);
    if ( heightDeviation < 2*EPS_H ) {
        md.group = Floor;
    } else {
        md.group = Foot;
    }
}


bool frameRegion(float4 position, float floorHeight, float factor) {
	float L = 0.5*(frontLength + backLength);
	float center = L - backLength;
	bool checkOuter = abs(position.z) < (1-factor)*(maxHalfWidth + widthFloorZone) && abs(position.x + center) < (1-factor)*(L + widthFloorZone);
	bool checkInner = abs(position.z) > (1+factor)*maxHalfWidth || abs(position.x + center) > (1+factor)*L;

	bool frameCheck = checkInner && checkOuter;
	bool heightCheck = abs(position.y - floorHeight) < maxHeight;
	if ( floorHeight == -10 )
		heightCheck = true;
	
	return frameCheck && heightCheck;
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
	
    bool check1 = position.x*position.x + position.z*position.z < halfLength*halfLength;
	
	bool frameCheck = frameRegion(position, floorHeight, 0);

    if (
		check1
		&&
		frameCheck
		&&
		confidence == 2
        ) {
        
        int i, j;
        float val;
        mapToCartesianTable(position, i, j, val);
        if ( i < 0 || j < 0 || i > gridNodeCount-1 || j > gridNodeCount-1 ) {
            return ;
        }
        
        device auto& md = myMeshData[i*gridNodeCount + j];
		
		auto shr = MedianSearcher(&md);
		shr.newValue(val);
		md.group = Floor;
//        markCartesianMeshNodes(md, floorHeight);
    }
}

vertex ParticleVertexOut gridCartesianMeshVertex( constant MyMeshData* myMeshData [[ buffer(kMyMesh) ]],
									 constant PointCloudUniforms &uniforms [[ buffer(kPointCloudUniforms) ]],
									 constant float& floorHeight [[ buffer(kHeight) ]],
									 unsigned int vid [[ vertex_id ]] ) {
	constant auto &md = myMeshData[vid];

	const auto nodeVal = md.mean;
	auto pos = restoreFromCartesianTable(nodeVal, vid);
//	auto saturation = static_cast<float>(MedianSearcher(&md).getLength()) / MAX_MESH_STATISTIC;
	auto saturation = 1;
	
	float4 color = colorCartesianPoint(pos.y - floorHeight, saturation);
//	float mixFactor = detectNodeOrientationToCamera(uniforms, pos, floorHeight);
//	float4 shined = shineDirection(color, mixFactor);
//	float4 colorised = saturateAsDistance(uniforms, md.depth, shined);

	float factor = 0.001;
	bool check1 = pos.x*pos.x + pos.z*pos.z < (1-factor)*(1-factor)*halfLength*halfLength;
	
	
	
	bool frameCheck = frameRegion(pos, floorHeight, factor);
	
	if ( check1 && frameCheck) {
		color.a = 1;
	} else {
		color.a = 0;
	}
	
	ParticleVertexOut pOut;
	pOut.position = projectOnScreen(uniforms, pos);
	pOut.color = color;
	return pOut;
}

// ------------------------- BASE SPHERICAL -------------------------------



float4x4 fromGlobalToObjectCS(float h) {
    return float4x4( float4( 1, 0, 0, 0),
                     float4( 0, 0, 1, 0),
                     float4( 0, 1, 0, 0),
                     float4( 0, 0, -h, 1)
                    );
}

float4x4 fromObjectToGlobalCS(float h) {
    return float4x4( float4( 1, 0, 0, 0),
                     float4( 0, 0, 1, 0),
                     float4( 0, 1, 0, 0),
                     float4( 0, h, 0, 1)
                    );
}


// cylindrical mapping
void mapToCylindricalTable(float floorHeight, float4 position, thread int& i, thread int& j, thread float& value) {
	const auto spos = fromGlobalToObjectCS(floorHeight)*position;
	
//	if (spos.y < 0) {
//		i = GRID_NODE_COUNT;
//		j = i;
//		value = 0;
//		return;
//	}

	auto phi = atan( spos.y / spos.x );
	if ( spos.x < 0 ) {
		phi += M_PI_F;
	}
	else if (spos.x >= 0 && spos.y < 0) {
		phi += 2*M_PI_F;
	} else {}
	
	i = round(spos.z/gridNodeDistCylindricalZ);
	j = round( phi / PHI_STEP );
	value = length(spos.xy);
}

float4 fromCylindricalToCartesian(float rho, int index) {
	const auto z = (index/GRID_NODE_COUNT)*gridNodeDistCylindricalZ;
	const auto phi = (index%GRID_NODE_COUNT)*PHI_STEP;
	
	float4 pos(1);
	pos.x = rho*cos(phi);
	pos.y = rho*sin(phi);
	pos.z = z;

	return pos;
}

float4 colorSphericalPoint(float floorDist, float rho, float saturation) {
    const float4 childUnexpected(247./255, 242./255, 26./255, 0);
    const float4 yellow(1, 0, 0, 0);
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
    
    auto h = md.mean;
    auto heightDeviation = abs(h*cos(thetaIndex*THETA_STEP));
    if ( heightDeviation < 2*EPS_H ) {
        md.group = Floor;
    } else {
        md.group = Foot;
    }
}





// --------------------- SPHERICAL GRID ------------------------------------

//enum Direction {
//	North,
//	South,
//	West,
//	East,
//	NotDefined
//};

float4 detectCameraPosition(constant PointCloudUniforms &uniforms) {
	constant auto& mat = uniforms.localToWorld;
	auto res = mat*float4(0, 0, 0, 1);
//	auto camPos = normalize(camOrigin);
//	auto camDirEnd = (mat*float4(0, 0, 1, 1)).xyz;
//	auto camDir = normalize(camDirEnd - camOrigin);
//	Direction res = NotDefined;
//	if (abs(camPos.x) > abs(camPos.z)) {
//		if (camPos.x < 0 && camDir.x > 0) {
//			res = North;
//		} else if ( camPos.x > 0 && camDir.x < 0 ) {
//			res = South;
//		}
//	} else {
//		if (camPos.z > 0 && camDir.z < 0) {
//			res = West;
//		} else if (camPos.z < 0 && camDir.z > 0) {
//			res = East;
//		}
//	}
	return res;
}


//float calcAngle(float4 camera, float4 point) {
//	thread const auto& rhoCam = camera.xz;
//	thread const auto& rhoPoint = point.xz;
//
//	return dot(rhoCam, rhoPoint);
//}

float calcOrientation(float floorHeight,
					  constant PointCloudUniforms &uniforms, constant MyMeshData* mesh, int vid ) {
	
	const auto nodeVal = mesh[vid].mean;
	auto pos = fromObjectToGlobalCS(floorHeight)*fromCylindricalToCartesian(nodeVal, vid);
	// направление обзора камеры в СК связанной с объектом наблюдения
	const auto camLocation = normalize(
									 (fromGlobalToObjectCS(floorHeight)*detectCameraPosition(uniforms)).xyz
									 -
									 (fromGlobalToObjectCS(floorHeight)*(pos)).xyz
								 );
	// нормаль в данном узле
	const auto normal = mesh[vid].normal;
	
	return dot(normal, camLocation);
}

float calcOrientation(float floorHeight,
					  constant PointCloudUniforms &uniforms, device MyMeshData* mesh, int vid ) {
	
	const auto nodeVal = mesh[vid].mean;
	auto pos = fromObjectToGlobalCS(floorHeight)*fromCylindricalToCartesian(nodeVal, vid);
	// направление обзора камеры в СК связанной с объектом наблюдения
	const auto camLocation = normalize(
									 (fromGlobalToObjectCS(floorHeight)*detectCameraPosition(uniforms)).xyz
									 -
									 (fromGlobalToObjectCS(floorHeight)*(pos)).xyz
								 );
	// нормаль в данном узле
	const auto normal = mesh[vid].normal;
	
	return dot(normal, camLocation);
}

// вычисление  угла градиента
float calcGrad(uint vid,
				constant float2 *gridPoints,
				constant PointCloudUniforms &uniforms,
				texture2d<float, access::sample> depthTexture,
				int imgWidth,
				int imgHeight) {
	
	float res = 0;
	if (
		static_cast<unsigned int>(imgWidth) <= vid &&
		vid < static_cast<unsigned int>(imgWidth*(imgHeight - 1))
		) {
		
		const auto v11 = vid;

		const auto v01 = v11 - imgWidth; // изменение вдоль Y
		const auto v00 = v01 - 1;
		const auto v02 = v01 + 1;
		
		const auto v10 = v11 - 1;
		const auto v12 = v11 + 1;
		
		const auto v21 = v11 + imgWidth; // изменение вдоль Y
		const auto v20 = v21 - 1;
		const auto v22 = v21 + 1;
		
		
		
		const auto t00 = gridPoints[v00] / uniforms.cameraResolution;
		const auto t01 = gridPoints[v01] / uniforms.cameraResolution;
		const auto t02 = gridPoints[v02] / uniforms.cameraResolution;
//		const auto t11 = gridPoints[v11] / uniforms.cameraResolution;
		const auto t10 = gridPoints[v10] / uniforms.cameraResolution;
		const auto t12 = gridPoints[v12] / uniforms.cameraResolution;
		
		const auto t20 = gridPoints[v20] / uniforms.cameraResolution;
		const auto t21 = gridPoints[v21] / uniforms.cameraResolution;
		const auto t22 = gridPoints[v22] / uniforms.cameraResolution;
		
		const auto dr = float2((t00 - t02).x, (t02 - t22).y);
		
		// Sample the depth map to get the depth value
		const auto f00 = depthTexture.sample(depthSampler, t00).r;
		const auto f01 = depthTexture.sample(depthSampler, t01).r;
		const auto f02 = depthTexture.sample(depthSampler, t02).r;
		const auto f10 = depthTexture.sample(depthSampler, t10).r;
		const auto f12 = depthTexture.sample(depthSampler, t12).r;
		const auto f20 = depthTexture.sample(depthSampler, t20).r;
		const auto f21 = depthTexture.sample(depthSampler, t21).r;
		const auto f22 = depthTexture.sample(depthSampler, t22).r;
		
		const auto df = 0.25*float2(f00 - f20 + 2*(f01 - f21) + f02 - f22,
							   f02 - f00 + 2*(f12 - f10) + f22 - f20);
		res = atan ( sqrt( dot(df, df) / dot(dr, dr) ) );
	}
	return res;
}


vertex void unprojectSphericalVertex(
                            uint vertexID [[vertex_id]],

                            constant PointCloudUniforms &uniforms [[buffer(kPointCloudUniforms)]],
                            constant float2 *gridPoints [[ buffer(kGridPoints) ]],
                            constant float& floorHeight[[ buffer(kHeight) ]],
                            device MyMeshData *myMeshData[[ buffer(kMyMesh) ]],
							constant int& imgWidth [[ buffer(kImgWidth) ]],
							constant int& imgHeight [[ buffer(kImgHeight) ]],
                            texture2d<float, access::sample> depthTexture [[texture(kTextureDepth)]],
                            texture2d<unsigned int, access::sample> confidenceTexture [[texture(kTextureConfidence)]]
                            ) {
    const auto gridPoint = gridPoints[vertexID];
	
    const auto texCoord = gridPoint / uniforms.cameraResolution;
    // Sample the depth map to get the depth value
    const auto depth = depthTexture.sample(depthSampler, texCoord).r;

    if (depth < minDistance ) {
        return;
    }

    // With a 2D point plus depth, we can now get its 3D position
    const auto pointLocation = worldPoint(gridPoint, depth, uniforms.cameraIntrinsicsInversed, uniforms.localToWorld);
	

    const auto confidence = confidenceTexture.sample(depthSampler, texCoord).r;

    bool check1 = pointLocation.x*pointLocation.x + pointLocation.z*pointLocation.z < RADIUS*RADIUS;
	bool checkHeight = pointLocation.y - floorHeight < maxHeight;
	bool checkWidth = abs(pointLocation.z) < maxHalfWidth;
	bool checkLength = (pointLocation.x < 0)? pointLocation.x > -frontLength: pointLocation.x < backLength;

    if (
        check1
		&&
		checkHeight
        &&
		checkWidth
		&&
		checkLength
		&&
        confidence == 2
        ) {

        int i, j;
        float val;
//        mapToSphericalTable(floorHeight, position, i, j, val);
		mapToCylindricalTable(floorHeight, pointLocation, i, j, val);
        if ( i < 0 || j < 0 || i > GRID_NODE_COUNT-1 || j > GRID_NODE_COUNT-1 ) {
            return ;
        }

		
        device auto& md = myMeshData[i*GRID_NODE_COUNT + j];
		
		auto grad = calcGrad(vertexID, gridPoints, uniforms, depthTexture, imgWidth, imgHeight);

		if (
//			orient <= 0 ||
			grad > 0.2*M_PI_2_F) {
			return;
		}
		
		auto orient = calcOrientation(floorHeight, uniforms, myMeshData, vertexID);
		if (orient > M_PI_4_F) {
			return;
		}
		
		md.gradVal = grad;
		md.depth = depth;

		MedianSearcher(&md).newValue(val);
        markSphericalMeshNodes(md, i);
    }
}

float4 shineDirection(float4 inColor, float mixFactor) {
	return mix(inColor, float4(1, 1, 0, 1), mixFactor);
}


float saturFunc(float depth) {
	auto x = depth - idealDist;
	auto n = 8.f;
	auto d = acceptanceZone/8;
	auto a = (x > 0)? (n-1)*d: d;
	auto y = (x/a)*(x/a);
	if (y > 1)
		y = 1;
	return y;
}

float4 saturateAsDistance(constant PointCloudUniforms& uniforms, float depth, const thread float4& color) {

	
	float param = saturFunc(depth);

	const auto value = dot( color.rgb, float3(0.299, 0.587, 0.114) );
	const auto gray = float4(value, value, value, 1);
	return mix(color, gray, param);
}



vertex ParticleVertexOut gridSphericalMeshVertex( constant MyMeshData* myMeshData [[ buffer(kMyMesh) ]],
                                     constant PointCloudUniforms &uniforms [[ buffer(kPointCloudUniforms) ]],
                                     constant float& floorHeight [[ buffer(kHeight) ]],
									 constant bool& isNotFreezed [[ buffer(kIsNotFreezed) ]],
                                     unsigned int vid [[ vertex_id ]] ) {
    constant auto &md = myMeshData[vid];

    const auto nodeVal = md.mean;
//    auto pos = restoreFromSphericalTable(floorHeight, nodeVal, vid);
	
	auto pos = fromObjectToGlobalCS(floorHeight)*fromCylindricalToCartesian(nodeVal, vid);
//
//	// направление обзора камеры в СК связанной с объектом наблюдения
//	const auto camLocation = normalize(
//										(toObjectCartesianBasis(floorHeight)*detectCameraPosition(uniforms)).xyz
//										-
//										(toObjectCartesianBasis(floorHeight)*(pos)).xyz
//									);
	// нормаль в данном узле
//	const auto normal = md.normal;
//	auto orient = dot(normal, camLocation);
	
//	auto orient = calcOrientation(floorHeight, uniforms, myMeshData, vid);
//	const auto saturation = (orient < 0)? 0: 0.7*orient;
//	const auto saturation = orient;
//	const auto saturation = 0.5;
	float4 color = colorSphericalPoint(abs(pos.y - floorHeight), nodeVal, 0.6);
	
//    auto saturation = static_cast<float>(MedianSearcher(&md).getLength()) / MAX_MESH_STATISTIC;
	
//	float mixFactor = detectCameraOrientation(uniforms, pos, floorHeight);
//	float4 shined = shineDirection(color, mixFactor);
//	float4 colorised = saturateAsDistance(uniforms, md.depth, shined);
	
//	auto location = detectCameraOrientation(uniforms);
//
//	if (location == North) {
//		color = float4(0,0,1,.1);
//	} else if (location == South) {
//		color = float4(1,0,0,.1);
//	} else if (location == East) {
//		color = float4(1,1,0,.1);
//	} else {
//		color = float4(0,1,0,.1);
//	}
	
//	auto color = float4(normal, saturation);
	
	
//	auto h = md.gradVal;
//	auto color = float4(h, 0, 0., 0.5);
//	auto color = mix(float4(1., 0., 0., 1.),
//					 float4(0.,0.,1., 1.), orient);

	
//	if (!isNotFreezed) {
//		color = float4(0.5, 0.5, 0., saturation);
//	}
	
    ParticleVertexOut pOut;
    pOut.position = projectOnScreen(uniforms, pos);
	pOut.color = color;
    return pOut;
}

// --------------------------------- BASE FRAGMENT SHADER ------------------------------------------



fragment float4 gridFragment(ParticleVertexOut in[[stage_in]]) {
    return in.color;
}

