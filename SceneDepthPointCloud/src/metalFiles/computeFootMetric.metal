#include <metal_stdlib>
#include <simd/simd.h>
#include "../MyMeshData.h"
#import "../ShaderTypes.h"

float4 fromGiperbolicToCartesian(float value, int index, bool doShift);
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

float3 calcCoord(device MyMeshData* mesh,
			int index) {
	device auto& value = mesh[index].mean;
	const auto r = fromGiperbolicToCartesian(value, index, true) + float4(0, 0, -mesh[index].heightCorrection, 0);
	return r.xyz;
}

//  проверка на то, что все узлы с номерами (i,j), (i+1,j), (i,j+1) лежат в одной и той же секции
bool checkThreePoints(int index) {
	const auto i = index / PHI_GRID_NODE_COUNT;
	const auto j = index % PHI_GRID_NODE_COUNT;
	bool halfTable = i/U_GRID_NODE_COUNT;
	if ( halfTable != (i+1)/U_GRID_NODE_COUNT ) { // по разные половины таблицы => разные секции
		return false;
	} else {	// половины таблицы совпадают
		const auto width = (halfTable == 0)? PHI_GRID_NODE_COUNT/4 : PHI_GRID_NODE_COUNT/2;
		if ( j/width == (j+1)/width ) {	// одинаковые секции
			return true;
		} else
			return false;
	}
}

bool inInnerSector(device MyMeshData* mesh, int index) {
	const auto i = index / PHI_GRID_NODE_COUNT;
	const auto j = index % PHI_GRID_NODE_COUNT;
	
	const auto dY = BOX_HALF_WIDTH;
	const auto dX = (i < U_GRID_NODE_COUNT) ? 2*BOX_HALF_LENGTH/3 : BOX_HALF_LENGTH/3;
	
	
	device auto& value = mesh[index].mean;
	const auto r = fromGiperbolicToCartesian(value, index, false);
	
	return abs(r.x) < dX && abs(r.y) < dY;
}


kernel void processSegmentation(
						   uint index [[ thread_position_in_grid ]],
						   device MyMeshData *myMeshData [[ buffer(kMyMesh) ]]
						   ) {
	device auto& mesh = myMeshData[index];
	
	if (mesh.mean == 0) {
		return;
	}
	
	if (mesh.group == Border) {
		return;
	}
	
	const auto criticalFloorDeviationHeight = 0.003;
	const auto r0 = calcCoord(myMeshData, index);
	
	if (!inInnerSector(myMeshData, index)) {
		mesh.group = ZoneUndefined;
	} else {
		if ( r0.z < criticalFloorDeviationHeight ) {
			mesh.group = Floor;
		} else {
			mesh.group = Foot;
		}
		if (checkThreePoints(index)) {	// тройка индексов подойдёт для оценки вектора нормали
			if ( criticalFloorDeviationHeight <= abs(r0.z) && abs(r0.z) < criticalFloorDeviationHeight + 0.01 ) {
				const auto rI = calcCoord(myMeshData, index + PHI_GRID_NODE_COUNT);
				const auto rJ = calcCoord(myMeshData, index + 1);
				const auto n = cross(rI-r0, rJ-r0);
				if ( abs(n.z) > length(n.xy) ) {
					mesh.group = FootDefect;
				}
			}
		}
	}
	
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
