#include <metal_stdlib>
#include <simd/simd.h>
#import "../ShaderTypes.h"
#include "../MyMeshData.h"
#include <metal_array>

using namespace metal;

constant float minDistance = 0.25;
constant float idealDist = 0.3;
constant float acceptanceZone = 0.2;


void mapToCartesianTable(float4 position, thread int& i, thread int& j, thread float& value);
float4 restoreFromCartesianTable(float h, int index);
float4x4 fromGlobalToObjectCS(float h);
float4x4 fromObjectToGlobalCS(float h);
float4 fromCylindricalToCartesian(float rho, int index);
void mapToGiperbolicTable(float4 spos, thread int& index, thread float& value);
float4 fromGiperbolicToCartesian(float value, int index);
bool inFootFrame(float4 spos);

//// -------------------------- BASE DEFINITIONS -----------------------------

class MedianSearcher {
	device MyMeshData* md;
	constant MyMeshData* mdConst;
	

	void moreModification(float value);
	
	void cycle();
	int incrementModulo(int x, int step = 1);
//	float moveMedian(int greater);
//	int detectShiftDirection(float median, float a, float b, bool add);
	
public:
	MedianSearcher(device MyMeshData* meshData): md(meshData), mdConst(nullptr) {}
	MedianSearcher(constant MyMeshData* meshData): md(nullptr), mdConst(meshData) {}
	void oldCode(float value);
	
	void newValue(float value);
	
	void newValueModi(float value);
	
};


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

float4 projectOnScreen(constant CoordData &uniforms, const thread float4& pos) {
    float4 res = uniforms.viewProjectionMatrix * pos;
    res /= res.w;
    return res;
}
	


// ------------------------------------- CARTESIAN ------------------------------------


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



bool frameRegion(float4 position, float floorHeight, float factor) {
	float L = 0.5*(BOX_FRONT_LENGTH + BOX_BACK_LENGTH);
	float center = L - BOX_BACK_LENGTH;
	bool checkOuter = abs(position.z) < (1-factor)*(BOX_HALF_WIDTH + BOX_FLOOR_ZONE) && abs(position.x + center) < (1-factor)*(L + BOX_FLOOR_ZONE);
	bool checkInner = abs(position.z) > (1+factor)*BOX_HALF_WIDTH || abs(position.x + center) > (1+factor)*L;

	bool frameCheck = checkInner && checkOuter;
	bool heightCheck = abs(position.y - floorHeight) < BOX_HEIGHT;
	if ( floorHeight == -10 )
		heightCheck = true;
	
	return frameCheck && heightCheck;
}



vertex void unprojectCartesianVertex(
                            uint vid [[vertex_id]],
                            constant CoordData &uniforms [[buffer(kPointCloudUniforms)]],
                            constant float2 *gridPoints [[ buffer(kGridPoints) ]],
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
	
	bool frameCheck = frameRegion(position, uniforms.floorHeight, 0);

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
        if ( i < 0 || j < 0 || i > GRID_NODE_COUNT-1 || j > GRID_NODE_COUNT-1 ) {
            return ;
        }
        
        device auto& md = myMeshData[i*GRID_NODE_COUNT + j];
		
		auto shr = MedianSearcher(&md);
		shr.newValue(val);
		md.group = Floor;
//        markCartesianMeshNodes(md, floorHeight);
    }
}



vertex ParticleVertexOut gridCartesianMeshVertex( constant MyMeshData* myMeshData [[ buffer(kMyMesh) ]],
									 constant CoordData &uniforms [[ buffer(kPointCloudUniforms) ]],
									 unsigned int vid [[ vertex_id ]] ) {
	constant auto &md = myMeshData[vid];

	const auto nodeVal = md.mean;
	auto pos = restoreFromCartesianTable(nodeVal, vid);
//	auto saturation = static_cast<float>(MedianSearcher(&md).getLength()) / MAX_MESH_STATISTIC;
	auto saturation = 1;
	
	float4 color = colorCartesianPoint(pos.y - uniforms.floorHeight, saturation);
//	float mixFactor = detectNodeOrientationToCamera(uniforms, pos, floorHeight);
//	float4 shined = shineDirection(color, mixFactor);
//	float4 colorised = saturateAsDistance(uniforms, md.depth, shined);

	float factor = 0.001;
	bool check1 = pos.x*pos.x + pos.z*pos.z < (1-factor)*(1-factor)*RADIUS*RADIUS;
	
	
	
	bool frameCheck = frameRegion(pos, uniforms.floorHeight, factor);
	
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








// --------------------- SPHERICAL GRID ------------------------------------

//enum Direction {
//	North,
//	South,
//	West,
//	East,
//	NotDefined
//};

float4 detectCameraPosition(constant CoordData &uniforms) {
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
					  constant CoordData &uniforms, constant MyMeshData* mesh, int vid ) {
	
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
					  constant CoordData &uniforms, device MyMeshData* mesh, int vid ) {
	
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



//bool checkDone(device MyMeshData* mesh, int index) {
//
//	device auto& md = mesh[index];
//	device auto& isDone = md.isDone;
//
//	if (isDone) {
//		return isDone;
//	}
//
//	if (md.totalSteps > MAX_MESH_STATISTIC) {
//		const auto i = index/GRID_NODE_COUNT;
//		if ( i < 0 && i < GRID_NODE_COUNT-1 ) {
//			const auto dr1 = mesh[index - GRID_NODE_COUNT].mean - md.mean;
//			const auto dr2 = mesh[index + GRID_NODE_COUNT].mean - md.mean;
//			const auto dr3 = mesh[index - 1].mean - md.mean;
//			const auto dr4 = mesh[index + 1].mean - md.mean;
//
//			const auto delta = 0.002;
//			if ( abs(dr1) < delta &&
//				 abs(dr2) < delta &&
//				 abs(dr3) < delta &&
//				 abs(dr4) < delta )
//				isDone = true;
//		}
//	}
//	return isDone;
//
//}




bool inScanArea(float4 spos) {
	bool checkWidth = abs(spos.y) < BOX_HALF_WIDTH;
	bool checkLength = (spos.x < 0)? spos.x > -BOX_FRONT_LENGTH: spos.x < BOX_BACK_LENGTH;
	return checkLength && checkWidth;
}

vertex void unprojectCylindricalVertex(
                            uint vertexID [[vertex_id]],
                            constant CoordData &uniforms [[buffer(kPointCloudUniforms)]],
                            constant float2 *gridPoints [[ buffer(kGridPoints) ]],
                            device MyMeshData *myMeshData[[ buffer(kMyMesh) ]],
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

	bool checkHeight = pointLocation.y - uniforms.floorHeight < BOX_HEIGHT;
	const auto spos = fromGlobalToObjectCS(uniforms.floorHeight)*pointLocation;
	bool frameCheck = inFootFrame(spos);
    if (
		checkHeight
        &&
		frameCheck
		&&
        confidence == 2
        ) {

        int index;
        float val;
		mapToGiperbolicTable(spos, index, val);
        if ( index < 0 || index > PHI_GRID_NODE_COUNT*U_GRID_NODE_COUNT-1 ) {
            return ;
        }

		
        device auto& md = myMeshData[index];
		

		MedianSearcher(&md).newValue(val);

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

float4 saturateAsDistance(constant CoordData& uniforms, float depth, const thread float4& color) {

	
	float param = saturFunc(depth);

	const auto value = dot( color.rgb, float3(0.299, 0.587, 0.114) );
	const auto gray = float4(value, value, value, 1);
	return mix(color, gray, param);
}

float4 colorPhi(const thread float* phi, int count, float4 inColor, int index) {
	for (int i=0; i < count; ++i) {
		if (index%PHI_GRID_NODE_COUNT == int(phi[i]/PHI_STEP)) {
			return float4(1, 0, 0, 1);
		}
	}
	return inColor;
}

float4 colorLengthDirection(float4 color, int index) {
	float phiArr[2] = {0, M_PI_F};
	return colorPhi(phiArr, 2, color, index);
}

float4 colorByGroup(float4 color, constant MyMeshData& mesh) {
	const auto group = mesh.group;
	if (group == Border) {
		return float4(0, 0, 1, 1);
	}
	if (group == Floor) {
//		return saturate(color + float4(0.5, 0, 0, 0));
		return float4(0, 1, 0, 1);
	}
	if (group == Foot) {
		return float4(1, 0, 0, 1);
	}
	if (group == Unknown) {
		return float4(1);
	}
	return color;
}


vertex ParticleVertexOut gridCylindricalMeshVertex( constant MyMeshData* myMeshData [[ buffer(kMyMesh) ]],
                                     constant CoordData &uniforms [[ buffer(kPointCloudUniforms) ]],
									 constant bool& isNotFreezed [[ buffer(kIsNotFreezed) ]],
                                     unsigned int vid [[ vertex_id ]] ) {
    constant auto &md = myMeshData[vid];

    const auto nodeVal = md.mean;
//    auto pos = restoreFromSphericalTable(floorHeight, nodeVal, vid);
	
	const auto spos = fromGiperbolicToCartesian(nodeVal, vid);
	auto pos = fromObjectToGlobalCS(uniforms.floorHeight)*spos;
	
	
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
	
	
	float4 color = colorSphericalPoint(abs(pos.y - uniforms.floorHeight), nodeVal, 0.6);
//	color = colorLengthDirection(color, vid);
	color = colorByGroup(color, md);
	
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
	
	
	
	if (myMeshData[vid].isDone) {
		color.a = 1;
	}
	
	
	// выводим только узлы принадлежащие рамке сканирования
	if (!inScanArea(spos)) {
		color.a = 0;
	}

//	Раскраска по координате v гиперболической системы
//	if (nodeVal > 0.002 && nodeVal < 0.004 ) {
//		color.r = 1;
//		color.g = 0;
//		color.b = 1;
//	}
	
    ParticleVertexOut pOut;
    pOut.position = projectOnScreen(uniforms, pos);
	pOut.color = color;
    return pOut;
}

vertex ParticleVertexOut metricVertex(
									  unsigned int index [[ vertex_id ]],
									  constant CoordData &uniforms [[ buffer(kPointCloudUniforms) ]],
									  constant BorderPoints* borderPoints [[ buffer(kBorderBuffer) ]]
									) {
	constant auto& bp = borderPoints[index];
	const auto pos = fromObjectToGlobalCS(uniforms.floorHeight)*float4(bp.mean, 1);
	auto color = float4(1, 1, 0, 1);

	
	ParticleVertexOut pOut;
	pOut.position = projectOnScreen(uniforms, pos);
	pOut.color = color;
	return pOut;
}

// --------------------------------- BASE FRAGMENT SHADER ------------------------------------------



fragment float4 gridFragment(ParticleVertexOut in[[stage_in]]) {
    return in.color;
}

