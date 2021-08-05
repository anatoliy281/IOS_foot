#include <metal_stdlib>
#include <simd/simd.h>
#include "../MyMeshData.h"
#import "../ShaderTypes.h"

float4 fromGiperbolicToCartesian(float value, int index);
bool inFootFrame(float4 spos);
bool markZoneOfUndefined(float2 spos);


using namespace metal;

constant auto gridTotalNodes = U_GRID_NODE_COUNT*PHI_GRID_NODE_COUNT;


bool inSector(int sector, int index) {
	const auto i = index / PHI_GRID_NODE_COUNT;
	const auto j = index % PHI_GRID_NODE_COUNT;
	int indSec = -1;
	if (i < U_GRID_NODE_COUNT) {
		if (0 < j && j < PHI_GRID_NODE_COUNT/4) {
			indSec = 0;
		} else if (PHI_GRID_NODE_COUNT/4 < j && j < PHI_GRID_NODE_COUNT/2) {
			indSec = 2;
		} else if (PHI_GRID_NODE_COUNT/2 < j && j < 3*PHI_GRID_NODE_COUNT/4) {
			indSec = 3;
		} else if (3*PHI_GRID_NODE_COUNT/4 < j && j < PHI_GRID_NODE_COUNT) {
			indSec = 5;
		}
	} else {
		if (0 < j && j < PHI_GRID_NODE_COUNT/2) {
			indSec = 1;
		} else {
			indSec = 4;
		}
	}
	
	return sector == indSec;
}

kernel void correctHeight(
						  uint index [[ thread_position_in_grid ]],
						  device MyMeshData *myMeshData [[ buffer(kMyMesh) ]],
						  constant ViewSector& sector [[ buffer(kViewSector) ]],
						  constant float& heightCorrection [[ buffer(kFloorShift)]]
						  ) {
	
	if (inSector(sector.number, index)) {
		myMeshData[index].heightCorrection = heightCorrection;
	}
}

//float calcDzDrho(device MyMeshData* mesh,
//					  int index,
//					  int delta) {
//	const auto stepIndex = delta*PHI_GRID_NODE_COUNT;
//
//	const auto index0 = index - stepIndex;
//	const auto indexN =  index + stepIndex;
//	if ( index0 < 0 || indexN >= 2*gridTotalNodes ) {
//		return 0;
//	}
////
////	const auto dU = 10;
////	const auto indexPlusdU = index + dU*PHI_GRID_NODE_COUNT;
////	const auto indexMinusdU = index - dU*PHI_GRID_NODE_COUNT;
////	if ( indexMinusdU < 0 || indexPlusdU > gridTotalNodes ) {
////		return 0;
////	}
////	if (mesh[indexPlusdU].group == Unknown || mesh[indexMinusdU].group == Unknown) {
////		return 0;
////	}
//
//	const auto r0 = fromGiperbolicToCartesian(mesh[index0].mean, index0);
//	const auto rN = fromGiperbolicToCartesian(mesh[indexN].mean, indexN);
//
//	const auto dR = r0 - rN;
////	if (length(r0.xy) < length(rN.xy)) {
////		return 0;
////	}
//
//	if (inFootFrame(r0) && inFootFrame(rN)) {
//		return dR.z / length(dR.xy);
//	} else {
//		return 0;
//	}
//
//}

float3 calcCoord(device MyMeshData* mesh,
			int index) {
	device auto& value = mesh[index].mean;
	const auto r = fromGiperbolicToCartesian(value, index) + float4(0, 0, -mesh[index].heightCorrection, 0);
	return r.xyz;
}


//constant float EpsilonSqured = 0.003*0.003;

//bool checkCoordSysBorder(int uCoord, int phiCoord, device MyMeshData* mesh) {
//	const auto uCoord0 = uCoord - 1;
//	const auto uCoord1 = uCoord + 1;
//
//	const auto index0 = uCoord0*PHI_GRID_NODE_COUNT + phiCoord;
//	const auto index1 = uCoord1*PHI_GRID_NODE_COUNT + phiCoord;
//	const auto index2 = uCoord*PHI_GRID_NODE_COUNT + phiCoord;
//
//	return mesh[index0].group != Unknown &&
//		   mesh[index1].group != Unknown &&
//		   mesh[index2].group != Unknown;
//
//}

kernel void processSegmentation(
						   uint index [[ thread_position_in_grid ]],
						   device MyMeshData *myMeshData [[ buffer(kMyMesh) ]]
//						   constant CoordData& coordData [[ buffer(kPointCloudUniforms) ]],
//						   constant float3& pointInRise [[ buffer(kRisePoint) ]],
//						   device BorderPoints* borderBuffer [[ buffer(kBorderBuffer) ]]
						   ) {
	if ( index < gridTotalNodes) {
		if (index + PHI_GRID_NODE_COUNT >= gridTotalNodes ) {
			return;
		}
	} else {
		if (index + PHI_GRID_NODE_COUNT >= 2*gridTotalNodes ) {
			return;
		}
	}
	
	device auto& mesh = myMeshData[index];
	
	if (mesh.mean == 0) {
		return;
	}
	
	const auto deltaN = 3;
	const auto criticalSlope = 1;
//	const auto criticalFloorHeight = 0.005;
	const auto criticalBorderHeight = 0.006
	;
	
//	const auto phiCoord = index%PHI_GRID_NODE_COUNT;
//	const auto vCoord = index/PHI_GRID_NODE_COUNT;
//	device auto& bp = borderBuffer[phiCoord];
	const auto r = calcCoord(myMeshData, index);
//	const auto s = calcDzDrho(myMeshData, index, deltaN);
//	const auto dr = rN - r0;
	

//	if ( s > criticalSlope &&
//		 h < criticalBorderHeight &&
//		 mesh.group != ZoneUndefined ) {
//		mesh.group = Border;
//		const auto i = (bp.len++)%MAX_BORDER_POINTS;
//		bp.coords[i] = float4(r, uCoord);
////		bp.tgAlpha[i] = s;
//	}
////	else if (bp.u_coord != 0) {
////		auto xyOut = int(index/PHI_GRID_NODE_COUNT) < bp.u_coord;
////		if ( xyOut ) {
////			mesh.group = Floor;
////		} else {
////			mesh.group = Foot;
////		}
////	}
//	else  {
	if (mesh.group != Border) {
		if (markZoneOfUndefined(r.xy)) {
			mesh.group = ZoneUndefined;
		} else {
//			if ( length(dr.xy)/abs(dr.z) > 2 ) {
			if ( abs(r.z) < 0.003 ) {
				mesh.group = Floor;
			} else {
				mesh.group = Foot;
			}
		}
	}
//	}
	
	// TODO доделать взятие области 
//	if ( length_squared(pointInRise) > 0 && length_squared(r.xy - pointInRise.xy) < EpsilonSqured ) {	// заполняем буфер в области подъёма
//		device auto& bpCenter = borderBuffer[PHI_GRID_NODE_COUNT+9];
//		bpCenter.coords[(bpCenter.len++)%MAX_BORDER_POINTS] = float4(r, 0);
//	}
	
}

// реализация нахождения границы
kernel void reductBorderBuffer(
							   uint index[[ thread_position_in_grid ]],
							   device BorderPoints* buffer[[ buffer(kBorderBuffer) ]]
							   ) {
	if ( index == PHI_GRID_NODE_COUNT+9 ) { // не понятно почему не проходит усреднение, поэтому код закомментирован
		device auto& bp = buffer[index];
		float4 mean = 0;
//		for (int i=0; i < MAX_BORDER_POINTS; ++i) {
//			mean += bp.coords[i];
//		}
//		mean /= MAX_BORDER_POINTS;
		bp.mean = mean.xyz;
	} else if ( index > PHI_GRID_NODE_COUNT  ) {
		return;
	} else {
		device auto& bp = buffer[index];
	//	auto len = min(bp.len, MAX_BORDER_POINTS);
	//	if (len != MAX_BORDER_POINTS) {
	//		return;
	//	}

		if (bp.len > 0) {
			float4 mean = 0;
			for (int i=0; i < (bp.len)%MAX_BORDER_POINTS; ++i) {
				if (length_squared(bp.coords[i]) > 0) {
					mean += bp.coords[i];
				}
	//			if (maxTangent < bp.tgAlpha[i]) {
	//				maxTangent = bp.tgAlpha[i];
	//				iMaxTangent = i;
	//			}
			}
			mean /= bp.len;
			bp.mean = mean.xyz;
	//		bp.mean = bp.coords[iMaxTangent].xyz;
			bp.typePoint = border;
			bp.u_coord = int(mean.w);
			bp.len = 0;
		} else {
			bp.typePoint = none;
			bp.u_coord = 0;
		}
	}
}
