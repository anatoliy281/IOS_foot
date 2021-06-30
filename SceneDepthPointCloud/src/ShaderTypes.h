/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Types and enums that are shared between shaders and the host app code.
*/

#ifndef ShaderTypes_h
#define ShaderTypes_h

#include <simd/simd.h>
#include "MyMeshData.h"

enum TextureIndices {
    kTextureY = 0,
    kTextureCbCr = 1,
    kTextureDepth = 2,
    kTextureConfidence = 3
};

enum BufferIndices {
    kHeelArea = 0,
    kGridPoints = 1,
    kMyMesh = 2,
    kVerteces = 4,
    kViewCorner = 5,
    kViewToCam = 6,
    kPointCloudUniforms = 8,
    kGistros = 9,
    kFrame = 11,
	kIsNotFreezed = 12,
	kImgWidth = 13,
	kImgHeight = 14,
	kFrontToe = 15,
	kBackHeel = 16,
	kBorderBuffer = 17,
	kRisePoint = 18,
	kViewSector = 19
};

struct CoordData {
    matrix_float4x4 viewProjectionMatrix;
    matrix_float4x4 localToWorld;
    matrix_float3x3 cameraIntrinsicsInversed;
    simd_float2 cameraResolution;
	float floorHeight;
};

struct ViewSector {
	int number;
	simd_float3 coord;
};

struct CameraView {
    simd_float2 viewVertices;
    simd_float2 viewTexCoords;
};

struct Gistro {
    simd_int2 mn;
};

enum MetricType {
	none = 0,		// not marked
	interval = 1,	// left side of interval
	metric = 3,   // metric index
	camera = 4,
	metricNow = 5
};

// структура хранит массив точек для вычисления границы перехода нога-пол + текущий размер
struct BorderPoints {
	simd_float4 coords[MAX_BORDER_POINTS]; // хранит значения координат
	float tgAlpha[MAX_BORDER_POINTS]; // хранит значения производных dZ/dRho (dRho^2 = dX^2 + dY^2)
	simd_float3 mean;	// контур найденный для группы coords
	int u_coord;		// хранит u-координату гиперболической системы точки контура (см. mean)
	enum MetricType typePoint;	// тип точки контура (см. mean)
	int len;	// текущее место записи измерений (в массив записывается модуль от данной величины и MAX_BORDER_POINTS) тем самым осуществляется цикличность
};

#endif /* ShaderTypes_h */
