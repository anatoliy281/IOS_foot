#include <metal_stdlib>
#include "../ShaderTypes.h"
//#include "MedianSearcher.metal"

using namespace metal;

kernel void addition_gistro( constant Gistro *leftArr        [[ buffer(0) ]],
                               constant Gistro *rightArr        [[ buffer(1) ]],
                               device Gistro* resArr            [[ buffer(2) ]],
                               uint         index [[ thread_position_in_grid ]] )
{
    resArr[index].mn = leftArr[index].mn + rightArr[index].mn;
}

kernel void convert_gistro( constant MyMeshData* in [[ buffer(0) ]],
                            device Gistro* out [[ buffer(1) ]],
                            constant float2& interval [[ buffer(2) ]],
                            uint index [[ thread_position_in_grid ]] )
{
    constant auto& md = in[index];
    device auto& gistro = out[index];
    
    if ( min(md.totalSteps, MAX_MESH_STATISTIC) == 0 ) {
        gistro.mn = int2(0);
    } else {
        const auto x = md.median;
        const auto c = (interval.x + interval.y)*0.5f;
        if ( x > interval.x || x < interval.y ) {
            gistro.mn = int2(0);
        } else if ( x < c ) {
            gistro.mn = int2(0, 1);
        } else {
            gistro.mn = int2(1, 0);
        }
    }
}
