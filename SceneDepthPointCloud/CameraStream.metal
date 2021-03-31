#include <metal_stdlib>

#import "ShaderTypes.h"

using namespace metal;

struct RGBVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

//
constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);

constant auto yCbCrToRGB = float4x4(
                                    float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
                                    float4(+0.0000f, -0.3441f,  1.7720f, +0.0000f),
                                    float4( 1.4020f, -0.7141f, +0.0000f, +0.0000f),
                                    float4(-0.7010f,  0.5291f, -0.8860f, +1.0000f)
                                    );

vertex RGBVertexOut cameraImageVertex( uint vid [[ vertex_id ]],
                                       constant CameraView* image [[ buffer(kViewCorner) ]],
                                       constant matrix_float3x3& viewToCamera[[ buffer(kViewToCam) ]]) {
    RGBVertexOut out;
    out.position = float4(image[vid].viewVertices, 0, 1);
    out.texCoord = ( float3(image[vid].viewTexCoords, 1)*viewToCamera ).xy;
    return out;
}

fragment float4 cameraImageFragment(RGBVertexOut in [[stage_in]],
                                    texture2d<float, access::sample> capturedImageTextureY[[ texture(kTextureY) ]],
                                    texture2d<float, access::sample> capturedImageTextureCbCr[[ texture(kTextureCbCr) ]]
                                  ) {
    const auto uv = in.texCoord;
    const auto ycbcr = float4( capturedImageTextureY.sample(colorSampler, uv).r,
                               capturedImageTextureCbCr.sample(colorSampler, uv).rg, 1);
    
    return float4(float3(yCbCrToRGB*ycbcr).rgb, 1);
}

struct ParticleVertexOut {
    float4 position [[position]];
    float pointSize [[point_size]] = POINT_SIZE;
    float4 color;
};

vertex ParticleVertexOut axisVertex( constant ColoredPoint* axis [[buffer(kVerteces)]],
                         constant PointCloudUniforms &uniforms [[ buffer(kPointCloudUniforms) ]],
                         unsigned int vid [[ vertex_id ]]
                         )
{
    ParticleVertexOut outPnt;
    outPnt.position = uniforms.viewProjectionMatrix * float4(axis[vid].position, 1);
    outPnt.color = ceil(float4(axis[vid].position, 1));
    return outPnt;
}

fragment float4 axisFragment(ParticleVertexOut in[[stage_in]])
{
    return in.color;
}
