#include <metal_stdlib>
#include <simd/simd.h>
#import "../ShaderTypes.h"
#include "../MyMeshData.h"
#include <metal_array>

using namespace metal;

constant float minDistance = 0.25;
constant float idealDist = 0.3;
constant float acceptanceZone = 0.2;




// -------------------------- BASE DEFINITIONS -----------------------------

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



void MedianSearcher::cycle() {
	md->bufModLen = incrementModulo(md->bufModLen);
	md->totalSteps += 1;
}

int MedianSearcher::incrementModulo(int x, int step) {
	return (x + step + MAX_MESH_STATISTIC)%MAX_MESH_STATISTIC;
}




void MedianSearcher::newValue(float value) {
	
//	modification(value);
	
	oldCode(value);
}

void MedianSearcher::oldCode(float value) {
	device auto& mean = md->mean;
	
	int n = md->bufModLen;
	md->buffer[n] = value;
	cycle();
	if ( md->bufModLen == md->totalSteps ) {
		mean = (mean*n + value) / (n + 1.f);
	} else {
		float newMean = 0;
		
		for (int i = 0; i < MAX_MESH_STATISTIC; ++i) {
			newMean += md->buffer[i];
		}
		newMean /= MAX_MESH_STATISTIC;
		mean = newMean;
	}
}

void MedianSearcher::newValueModi(float value) {
	device auto& mean = md->mean;
	
	cycle();	// пересчёт индекса массива с учётом цикличности!
	
//	md->totalSteps += 1;
	if ( md->totalSteps <= MAX_MESH_STATISTIC ) { // md->totalStep пересчитан!!! и мы на первой итерации циклич. списка, т.е. продолжаем его заполнение пока его длина не достигнет MAX_MESH_STATISTIC
		int n = md->totalSteps;	// здесь 1 <= n <= (MAX_MESH_STATISTIC - 1)
		mean = (mean*(n-1) + value) / n;
		md->buffer[n-1] = value;	// пополнили буфер для нужд пересчёта при проходе по циклическим шагам
	} else {
		const auto nc = md->bufModLen;
//		const auto nc = md->totalSteps%MAX_MESH_STATISTIC;
		const auto oldValue = md->buffer[nc-1];
		md->buffer[nc-1] = value;
		mean += ((value - oldValue) / MAX_MESH_STATISTIC);
	}
	
}


void MedianSearcher::moreModification(float value) {
	device auto& mean = md->mean;
	
	cycle();	// пересчёт индекса массива с учётом цикличности!
	
	const auto nc = md->bufModLen;
	const auto oldValue = md->buffer[nc-1];
	md->buffer[nc-1] = value;
	mean += ((value - oldValue) / MAX_MESH_STATISTIC);
	
}


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

// ------------------------- OBJECT CS -------------------------------
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


float4 fromCylindricalToCartesian(float rho, int index) {
	const auto z = (index/PHI_GRID_NODE_COUNT)*gridNodeDistCylindricalZ;
	const auto phi = (index%PHI_GRID_NODE_COUNT)*PHI_STEP;
	
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


// ------------------ GIPERBOLIC ---------------------------
// spos - координаты точки в СК объекта наблюдения
// index - определяет положение в таблице
// value - усреднённое значение по поверхности
void mapToGiperbolicTable(float4 spos, thread int& index, thread float& value) {

	auto phase = 0.f;
	if ( spos.x < 0 ) {
		phase = M_PI_F;
	} else if (spos.y < 0) {
		phase = 2*M_PI_F;
	}
	auto phi = atan( spos.y / spos.x ) + phase;
	int j = round( phi / PHI_STEP );
	
	const auto rho = length(spos.xy);
	int i = round( (rho*rho - spos.z*spos.z) / U_STEP )	+ U0_GRID_NODE_COUNT;

	value = 2*rho*spos.z;
	index = i*PHI_GRID_NODE_COUNT + j;
}


float4 fromGiperbolicToCartesian(float value, int index) {
	const auto u_coord = ( index/PHI_GRID_NODE_COUNT - U0_GRID_NODE_COUNT )*U_STEP;
	const auto v_coord = value;
	
	const auto uv_sqrt = sqrt(v_coord*v_coord + u_coord*u_coord);
	const auto rho = sqrt(0.5f*(u_coord + uv_sqrt));
	const auto h = sqrt(rho*rho - u_coord);
	
	const auto phi = (index%PHI_GRID_NODE_COUNT)*PHI_STEP;
	
	float4 pos(1);
	pos.x = rho*cos(phi);
	pos.y = rho*sin(phi);
	pos.z = h;

	return pos;
}


vertex void unprojectCylindricalVertex(
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
    const auto depth = depthTexture.sample(depthSampler, texCoord).r;

    if (depth < minDistance ) {
        return;
    }

    // With a 2D point plus depth, we can now get its 3D position
    const auto pointLocation = worldPoint(gridPoint, depth, uniforms.cameraIntrinsicsInversed, uniforms.localToWorld);
	

    const auto confidence = confidenceTexture.sample(depthSampler, texCoord).r;

    bool check1 = pointLocation.x*pointLocation.x + pointLocation.z*pointLocation.z < RADIUS*RADIUS;
	bool checkHeight = pointLocation.y - floorHeight < BOX_HEIGHT;
	bool checkWidth = abs(pointLocation.z) < BOX_HALF_WIDTH;
	bool checkLength = (pointLocation.x < 0)? pointLocation.x > -BOX_FRONT_LENGTH: pointLocation.x < BOX_BACK_LENGTH;

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

        int index;
        float val;
		const auto spos = fromGlobalToObjectCS(floorHeight)*pointLocation;
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

float4 saturateAsDistance(constant PointCloudUniforms& uniforms, float depth, const thread float4& color) {

	
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

float4 colorHeight(const thread float* heights, int count, float4 inColor, int index) {
	for (int i=0; i < count; ++i) {
		if (index/PHI_GRID_NODE_COUNT == int(heights[i]/gridNodeDistCylindricalZ)) {
			return float4(0, 1, 0, 1);
		}
	}
	return inColor;
}

vertex ParticleVertexOut gridCylindricalMeshVertex( constant MyMeshData* myMeshData [[ buffer(kMyMesh) ]],
                                     constant PointCloudUniforms &uniforms [[ buffer(kPointCloudUniforms) ]],
                                     constant float& floorHeight [[ buffer(kHeight) ]],
									 constant bool& isNotFreezed [[ buffer(kIsNotFreezed) ]],
                                     unsigned int vid [[ vertex_id ]] ) {
    constant auto &md = myMeshData[vid];

    const auto nodeVal = md.mean;
//    auto pos = restoreFromSphericalTable(floorHeight, nodeVal, vid);
	
	auto pos = fromObjectToGlobalCS(floorHeight)*fromGiperbolicToCartesian(nodeVal, vid);
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
	
	float phiArr[2] = {0, M_PI_F};
	
	if (myMeshData[vid].isDone) {
		color.a = 1;
	}
	
	color = colorPhi(phiArr, 2,
					color,
						vid);
	
    ParticleVertexOut pOut;
    pOut.position = projectOnScreen(uniforms, pos);
	pOut.color = colorPhi(phiArr, 2, color, vid);
    return pOut;
}

vertex ParticleVertexOut metricVertex(
									constant PointCloudUniforms &uniforms [[ buffer(kPointCloudUniforms) ]],
									constant float& floorHeight [[ buffer(kHeight) ]],
									constant GridPoint* metricData [[ buffer(kFrontToe) ]],
									unsigned int vid [[ vertex_id ]] ) {
	constant auto& md = metricData[vid];
	const auto pos = fromObjectToGlobalCS(floorHeight)*fromGiperbolicToCartesian(md.rho, md.index);
	
	auto color = float4(0, 1, 0, 1);
	
	if (md.checked == 0) {
		color.a = 0.1;
	}
	
	ParticleVertexOut pOut;
	pOut.position = projectOnScreen(uniforms, pos);
	pOut.color = color;
	return pOut;
}

// --------------------------------- BASE FRAGMENT SHADER ------------------------------------------



fragment float4 gridFragment(ParticleVertexOut in[[stage_in]]) {
    return in.color;
}

