//
//  functions.metal
//  SceneDepthPointCloud
//
//  Created by Анатолий Чернов on 11.06.2021.
//  Copyright © 2021 Apple. All rights reserved.
//

#include <metal_stdlib>
#include "../MyMeshData.h"

using namespace metal;

constant float gridNodeDist = 2*RADIUS / GRID_NODE_COUNT;
constant float gridNodeDistCylindricalZ = 0.5*gridNodeDist;


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

constant auto k = 0.5;

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
	int i = round( (k*k*rho*rho - spos.z*spos.z) / U_STEP )	+ U0_GRID_NODE_COUNT;

	value = 2*rho*spos.z;
	index = i*PHI_GRID_NODE_COUNT + j;
}


float4 fromGiperbolicToCartesian(float value, int index) {
	
	const auto u_coord = ( index/PHI_GRID_NODE_COUNT - U0_GRID_NODE_COUNT )*U_STEP;
	const auto v_coord = value;
	
	const auto uv_sqrt = sqrt(k*k*v_coord*v_coord + u_coord*u_coord);
	const auto rho = sqrt(0.5f*(u_coord + uv_sqrt)) / k;
	const auto h = sqrt(k*k*rho*rho - u_coord);
	
	const auto phi = (index%PHI_GRID_NODE_COUNT)*PHI_STEP;
	
	float4 pos(1);
	pos.x = rho*cos(phi);
	pos.y = rho*sin(phi);
	pos.z = h;

	return pos;
}

bool inFootFrame(float4 spos) {
	bool checkWidth = abs(spos.y) < BOX_HALF_WIDTH;
	bool checkLength = (spos.x < 0)? spos.x > -BOX_FRONT_LENGTH: spos.x < BOX_BACK_LENGTH;
	return checkWidth && checkLength;
}

