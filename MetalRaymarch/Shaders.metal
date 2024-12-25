//
//  Shaders.metal
//

// File for Metal kernel and shader functions

#include <metal_stdlib>
#include <simd/simd.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#import "ShaderTypes.h"

using namespace metal;

typedef struct
{
    float3 position [[attribute(VertexAttributePosition)]];
    float2 texCoord [[attribute(VertexAttributeTexcoord)]];
} Vertex;

typedef struct
{
    float4 position [[position]];
    float2 texCoord;
    float time;
} ColorInOut;

vertex ColorInOut vertexShader(Vertex in [[stage_in]],
                               ushort ampId [[amplification_id]],
                               constant UniformsArray & uniformsArray [[ buffer(BufferIndexUniforms) ]])
{
    ColorInOut out;

    Uniforms uniforms = uniformsArray.uniforms[ampId];
    
    float4 position = float4(in.position, 1);
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * position;
    
    out.texCoord = in.texCoord;
    out.time = uniforms.time;
    
    return out;
}

#define ITERATIONS 128
#define MIN_DIST 0.001
#define THICKNESS 0.1
#define SUPER_QUAD_POWER 8.0

float rand(float3 r)
{
    return fract(sin(dot(r.xy, float2(1.38984 * sin(r.z), 1.13233 * cos(r.z)))) * 653758.5453);
}

float truchetarc(float3 pos)
{
    float r = length(pos.xy);
    return pow(pow(abs(r - 0.5), SUPER_QUAD_POWER) + pow(abs(pos.z - 0.5), SUPER_QUAD_POWER), 1.0/SUPER_QUAD_POWER) - THICKNESS;
}

float truchetcell(float3 pos)
{
    return min(
               min(
                   truchetarc(pos),
                   truchetarc(float3(pos.z, 1 - pos.x, pos.y))),
               truchetarc(float3(1 - pos.y, 1 - pos.z, pos.x)));
}

float distfunc(float3 pos)
{
    float3 cellpos = fract(pos);
    float3 gridpos = floor(pos);

    float rnd = rand(gridpos);

    if(rnd < 1.0 / 8) return truchetcell(float3(cellpos.x, cellpos.y, cellpos.z));
    else if(rnd < 2.0 / 8) return truchetcell(float3(cellpos.x, 1 - cellpos.y, cellpos.z));
    else if(rnd < 3.0 / 8) return truchetcell(float3(1 - cellpos.x, cellpos.y, cellpos.z));
    else if(rnd < 4.0 / 8) return truchetcell(float3(1 - cellpos.x, 1 - cellpos.y, cellpos.z));
    else if(rnd < 5.0 / 8) return truchetcell(float3(cellpos.y, cellpos.x, 1 - cellpos.z));
    else if(rnd < 6.0 / 8) return truchetcell(float3(cellpos.y, 1 - cellpos.x, 1 - cellpos.z));
    else if(rnd < 7.0 / 8) return truchetcell(float3(1 - cellpos.y, cellpos.x, 1 - cellpos.z));
    else return truchetcell(float3(1 - cellpos.y, 1 - cellpos.x, 1 - cellpos.z));
}

float3 gradient(float3 pos)
{
    const float eps = 0.0001;
    float mid = distfunc(pos);
    return float3(
        distfunc(pos + float3(eps, 0, 0)) - mid,
        distfunc(pos + float3(0, eps, 0)) - mid,
        distfunc(pos + float3(0, 0, eps)) - mid);
}

float4 rayMarch(thread float3 ro, thread float3 rd, thread float3 &normal)
{
    float3 rp = ro;
    
    float i = float(ITERATIONS);
    for(int j = 0; j < ITERATIONS; j++)
    {
        float dist = distfunc(rp);
        rp += dist * rd;

        if(abs(dist) < MIN_DIST)
        {
            i = float(j);
            break;
        }
    }

    normal = normalize(gradient(rp));

    float ao = 1 - i / float(ITERATIONS);
    float what = pow(max(0.0, dot(normal, -rd)), 2);
    float light = ao * what * 1.4;

    float3 col = (cos(rp / 2) + 2) / 3;

    return float4(col * light, 1);
}

float3 uvToDir(thread float2 uv) // uv: -1..1
{
    float2 uvRad = float2(uv.x * M_PI_F, uv.y * M_PI_F / 2); // -pi..pi, -pi/2..pi/2
    float2 xz = float2(sin(uvRad.x), cos(uvRad.x));
    return float3(xz.x * cos(uvRad.y), sin(uvRad.y), xz.y * cos(uvRad.y));
}

float2 dirToUv(thread float3 dir)
{
    float vert = atan2(dir.y, sqrt(dir.x * dir.x + dir.z * dir.z));
    float hor = atan2(dir.z, dir.x);
    return float2(hor / M_PI_F, vert / (M_PI_F / 2));
}

fragment float4 fragmentShader(ColorInOut in [[stage_in]],
                               texture2d<half> cubeMap [[texture(TextureIndexColor)]])
{
    float t = in.time / 3;
    
    float3 ro = float3(2 * (sin(t + sin(2 * t) / 2) / 2 + 0.5),
                       2 * (sin(t - sin(2 * t) / 2 - M_PI_F / 2) / 2 + 0.5),
                       2 * ((-2.0 * (t - sin(4 * t) / 4) / M_PI_F) + 0.1));

    float3 rd = uvToDir(in.texCoord * 2 - 1);

    matrix_float3x3 m = matrix_float3x3(0, 1, 0, -sin(t), 0, cos(t), cos(t), 0, sin(t));
    rd = m * m * m * m * rd;
    
    float3 normal;
    float4 color = rayMarch(ro, rd, normal);
    
    float3 reflected = reflect(rd, normal);
    float2 normUv = dirToUv(reflected);
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);
    
    float4 reflection = float4(cubeMap.sample(colorSampler, normUv));

    return color + reflection * 0.2;
}
