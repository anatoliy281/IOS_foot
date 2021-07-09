#include <metal_stdlib>
#include "../MyMeshData.h"
#import "../ShaderTypes.h"

using namespace metal;

class MedianSearcher {
	device MyMeshData* md;
	constant MyMeshData* mdConst;

public:
	MedianSearcher(device MyMeshData* meshData): md(meshData), mdConst(nullptr) {}
	void newValue(float value);
};


kernel void makeEqual(
				 uint index [[ thread_position_in_grid ]],
				 device MyMeshData *myMeshData [[ buffer(kMyMesh) ]],
				 constant int& sessionFrameCount [[ buffer(0) ]]
				 ) {
	device auto& md = myMeshData[index];
	if ( md.justRefilled == 0 ) {
		MedianSearcher(&md).newValue(-1);	// значение передаваемое в newValue задаёт направление и скорость сдвига среднего значения узла
	}
	md.justRefilled = 0;	// обнуление счётчика
}
