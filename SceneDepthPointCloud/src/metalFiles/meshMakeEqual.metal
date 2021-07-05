#include <metal_stdlib>
#include "../MyMeshData.h"
#import "../ShaderTypes.h"

using namespace metal;

class MedianSearcher {
	device MyMeshData* md;
	constant MyMeshData* mdConst;

public:
	MedianSearcher(device MyMeshData* meshData): md(meshData), mdConst(nullptr) {}
	void newValue(float value, int count);
};


kernel void makeEqual(
				 uint index [[ thread_position_in_grid ]],
				 device MyMeshData *myMeshData [[ buffer(kMyMesh) ]],
				 constant int& sessionFrameCount [[ buffer(0) ]]
				 ) {
	const int criticalFrameDelta = 10;
	device auto& md = myMeshData[index];
	if ( sessionFrameCount - md.totalSteps > criticalFrameDelta ) {
		MedianSearcher(&md).newValue(0, criticalFrameDelta);
	}
}
