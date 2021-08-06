#include <metal_stdlib>
#include "../MyMeshData.h"

using namespace metal;

constant float gridNodeDist = 2*RADIUS / GRID_NODE_COUNT;
constant float gridNodeDistCylindricalZ = 0.5*gridNodeDist;


bool markZoneOfUndefined(float2 spos) {
	const auto eps = 0.003;
	const auto hw = abs(BOX_HALF_WIDTH - abs(spos.y)) < eps;
	const auto hl = abs(BOX_HALF_LENGTH - abs(spos.x)) < eps;
	const auto hl3 = abs(BOX_HALF_LENGTH*0.33 - abs(spos.x)) < eps;
	const auto hw0 = abs(spos.y) < eps;
	
	return hw || hl || hl3 || hw0;
}

void mapToCartesianTable(float4 position, thread int& i, thread int& j, thread float& value) {
	i = round(position.x/gridNodeDist) + GRID_NODE_COUNT/2;
	j = round(position.z/gridNodeDist) + GRID_NODE_COUNT/2;
	value = position.y;
}

float4 restoreFromCartesianTable(float h, int index) {
	float4 pos(1);
	pos.x = (index/GRID_NODE_COUNT)*gridNodeDist - RADIUS;
	pos.z = (index%GRID_NODE_COUNT)*gridNodeDist - RADIUS;
	pos.y = h;
	
	return pos;
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

void mapToCylindricalTable(float4 spos, thread int& i, thread int& j, thread float& value) {
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
	const auto z = (index/PHI_GRID_NODE_COUNT)*gridNodeDistCylindricalZ;
	const auto phi = (index%PHI_GRID_NODE_COUNT)*PHI_STEP;
	
	float4 pos(1);
	pos.x = rho*cos(phi);
	pos.y = rho*sin(phi);
	pos.z = z;

	return pos;
}

// ------------------ GIPERBOLIC ---------------------------
// spos - координаты точки в СК объекта наблюдения
// index - определяет положение в таблице
// value - усреднённое значение по поверхности

constant auto k = 1;
constant auto h0 = -0.03;

// положения смещения систем координат (криволинейных и локальных)
constant float3 shiftsCS[6] = {
	float3(-BOX_HALF_LENGTH, -BOX_HALF_WIDTH, 0),
	float3( 0,               -BOX_HALF_WIDTH, 0),
	float3( BOX_HALF_LENGTH, -BOX_HALF_WIDTH, 0),
	float3( BOX_HALF_LENGTH,  BOX_HALF_WIDTH, 0),
	float3( 0,                BOX_HALF_WIDTH, 0),
	float3(-BOX_HALF_LENGTH,  BOX_HALF_WIDTH, 0)
};



void mapToGiperbolicTable(float4 spos, int sector, thread int& index, thread float& value) {
	auto r = spos.xyz - shiftsCS[sector]; // определение смещения ЛКС в зависимости от квадранта
	int bufferHalf = (sector == 1 || sector == 4) ? 1 : 0;
	
	float phase = 0; 	// определение фазы в определении полярного угла
	if ( r.x < 0 ) {
		phase = M_PI_F;
	} else if (r.y < 0) {
		phase = 2*M_PI_F;
	}
	auto phi = atan( r.y / r.x ) + phase;
	int j = round( phi / PHI_STEP );
	
	const auto rho = length(r.xy);
	const auto h = r.z;
	
	const auto u = k*k*rho*rho - (h-h0)*(h-h0);
	const auto v = 2*rho*(h-h0);
	
	value = u;
	const auto i = round( v / U_STEP ) + bufferHalf*U_GRID_NODE_COUNT;
	
	index = i*PHI_GRID_NODE_COUNT + j;
}


float4 fromGiperbolicToCartesian(float value, int index, bool doShift) {
	
	const auto u_coord = value;
	
	const auto i = index/PHI_GRID_NODE_COUNT;
	const auto halfTable = (i >= U_GRID_NODE_COUNT) ? 1: 0;
	auto v_coord = (i - halfTable*U_GRID_NODE_COUNT)*U_STEP;
	
	if (u_coord == 0) {
		v_coord = 0;
	}
	
//	const auto u_coord = ( index/PHI_GRID_NODE_COUNT - U0_GRID_NODE_COUNT )*U_STEP;
//	const auto v_coord = value;
	
	const auto uv_sqrt = sqrt(k*k*v_coord*v_coord + u_coord*u_coord);
	const auto rho = sqrt(0.5f*(u_coord + uv_sqrt)) / k;
	const auto h = sqrt(k*k*rho*rho - u_coord) + h0;
	
	const auto phi = (index%PHI_GRID_NODE_COUNT)*PHI_STEP;
	
	float3 pos(rho*cos(phi), rho*sin(phi), h);
	
	
	if (doShift) {
		// поменять местами квадранты 0<->3, 2<->5, 1<->4
		if (halfTable == 0) {
			if ( (M_PI_F < phi) && (phi <= 1.5*M_PI_F) ) {
				pos += shiftsCS[3];
			} else if ( (1.5*M_PI_F < phi) && (phi <= 2*M_PI_F) ) {
				pos += shiftsCS[5];
			} else if ( (0 < phi) && (phi <= M_PI_2_F) ) {
				pos += shiftsCS[0];
			} else if ( (M_PI_2_F < phi) && (phi <= M_PI_F) ) {
				pos += shiftsCS[2];
			} else { // так не бывает...
				return float4();
			}
			
		} else {
			if ( (M_PI_F < phi) && (phi <= 2*M_PI_F) ) {
				pos += shiftsCS[4];
			} else {
				pos += shiftsCS[1];
			}
		}
	}
	
	return float4(pos, 1);
}

bool inFootFrame(float4 spos) {
	bool checkWidth = abs(spos.y) < BOX_HALF_WIDTH;
	bool checkLength = abs(spos.x) < BOX_HALF_LENGTH;
	bool checkHeight = abs(spos.z) < BOX_HEIGHT;
	return checkWidth && checkLength && checkHeight;
}

