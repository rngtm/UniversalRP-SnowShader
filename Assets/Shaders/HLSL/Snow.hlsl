#ifndef UNIVERSAL_SNOW_PASS_INCLUDED
#define UNIVERSAL_SNOW_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Noise.hlsl"

// // -------------------------------------
// // 定数の定義
// CBUFFER_START(UnityPerMaterial)
// // float
// half _SnowAmount;
// half _SnowSpecularGloss;
// half _NoisePositionScale;
// half _NoiseInclinationScale;
// half _DiffuseNormalNoiseScale; // ディフューズ項の法線に加えるノイズ強度
// half _SpecularNormalNoiseScale; // スペキュラー項の法線に加えるノイズ強度
// // vector
// half3 _SnowDirection;
// half4 _SnowDotNormalRemap;
// // color
// half4 _DiffuseColor;
// half4 _SpecularColor;
// CBUFFER_END

// -------------------------------------
// 頂点シェーダーへの入力を格納するstruct
struct Attributes
{
    float4 positionOS   : POSITION;
    float3 normalOS     : NORMAL;
    float4 tangentOS    : TANGENT;
    float2 texcoord     : TEXCOORD0;
    float2 lightmapUV   : TEXCOORD1;
    UNITY_VERTEX_INPUT_INSTANCE_ID
};

// -------------------------------------
// フラグメントシェーダーへの入力を格納するstruct
struct Varyings
{
    float2 uv                       : TEXCOORD0;
    DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 1);

    float3 positionWS               : TEXCOORD2;
    float3 normalWS                 : TEXCOORD3;
#ifdef _NORMALMAP
    float4 tangentWS                : TEXCOORD4;    // xyz: tangent, w: sign
#endif
    float3 viewDirWS                : TEXCOORD5;

    half4 fogFactorAndVertexLight   : TEXCOORD6; // x: fogFactor, yzw: vertex light

    float4 shadowCoord              : TEXCOORD7;
    
    float4 positionOS               : TEXCOORD8; // position (object space)

    float4 positionCS               : SV_POSITION;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

// valueを範囲を[x, y]から[z, w]へ変換する 
float remap(float value, float4 range)
{
    return (value - range.x) * (range.w - range.z) / (range.y - range.x) + range.z;
}

// 頂点シェーダー
Varyings SnowVert(Attributes input)
{
    Varyings output = (Varyings)0;

    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_TRANSFER_INSTANCE_ID(input, output);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
    
    // normalWS and tangentWS already normalize.
    // this is required to avoid skewing the direction during interpolation
    // also required for per-vertex lighting and SH evaluation
    VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
    float3 viewDirWS = GetCameraPositionWS() - vertexInput.positionWS;
    half3 vertexLight = VertexLighting(vertexInput.positionWS, normalInput.normalWS);
    half fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

    output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);

    // already normalized from normal transform to WS.
    output.normalWS = normalInput.normalWS;
    output.viewDirWS = viewDirWS;
#ifdef _NORMALMAP
    real sign = input.tangentOS.w * GetOddNegativeScale();
    output.tangentWS = half4(normalInput.tangentWS.xyz, sign);
#endif

    OUTPUT_LIGHTMAP_UV(input.lightmapUV, unity_LightmapST, output.lightmapUV);
    OUTPUT_SH(output.normalWS.xyz, output.vertexSH);

    output.fogFactorAndVertexLight = half4(fogFactor, vertexLight);

#if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
    output.positionWS = vertexInput.positionWS;
#endif

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    output.shadowCoord = GetShadowCoord(vertexInput);
#endif

    output.positionCS = vertexInput.positionCS;
    output.positionOS = input.positionOS;
    
    return output;
}

// 積雪レンダリング用データ
struct SnowData {
    float fp;
    float3 diffuseNormal; // ディフューズ用Normal
    float3 specularNormal; // スペキュラー用Normal
};

// 積雪に使用する データの計算
void InitializeSnowData(Varyings input, out SnowData snowData) {

    float3 snowDir = normalize(_SnowDirection); // 雪の向き
    half3 noise = fbm(input.positionOS.xyz * _NoisePositionScale);

    // fe : 露出関数の値
    float fe = _SnowAmount; 
    
    // dE : 露出関数をスクリーンスペースで微分したもの (今回は常に同じ値をとるので0を入れておく)
    float3 dE = float3(0.0, 0.0, 0.0);
    
    // finc : 面の傾きの雪への寄与度
    float nDotS = dot(input.normalWS, snowDir); // 面の傾きが積雪に影響する成分
    nDotS = remap(nDotS, _SnowDotNormalRemap);
    
    // 面の傾きの積雪への寄与度
    float finc = nDotS // 面の傾きによる積雪量のコントロール
     + _NoiseInclinationScale * length(noise); // ノイズを加える
        
    // fp : 積雪予測関数 (雪が積もる量)
    snowData.fp = saturate(fe * finc);
    
    // 雪の照明計算に使う法線
    snowData.diffuseNormal = normalize(input.normalWS + snowData.fp  * noise * _DiffuseNormalNoiseScale + dE); 
    snowData.specularNormal = normalize(input.normalWS + snowData.fp * noise * _SpecularNormalNoiseScale + dE); 
}

// InputData作成
void InitializeInputData(Varyings input, half3 normalTS, out InputData inputData)
{
    inputData = (InputData)0;

#if defined(REQUIRES_WORLD_SPACE_POS_INTERPOLATOR)
    inputData.positionWS = input.positionWS;
#endif

    half3 viewDirWS = SafeNormalize(input.viewDirWS);
#ifdef _NORMALMAP 
    float sgn = input.tangentWS.w;      // should be either +1 or -1
    float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
    inputData.normalWS = TransformTangentToWorld(normalTS, half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz));
#else
    inputData.normalWS = input.normalWS;
#endif

    inputData.normalWS = NormalizeNormalPerPixel(inputData.normalWS);
    inputData.viewDirectionWS = viewDirWS;

#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
    inputData.shadowCoord = input.shadowCoord;
#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
    inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
#else
    inputData.shadowCoord = float4(0, 0, 0, 0);
#endif


    inputData.fogCoord = input.fogFactorAndVertexLight.x;
    inputData.vertexLighting = input.fogFactorAndVertexLight.yzw;
    inputData.bakedGI = SAMPLE_GI(input.lightmapUV, input.vertexSH, inputData.normalWS);
}

// 積雪用 BlinnPhongシェーディング
half4 SnowFragmentBlinnPhong(InputData inputData, SnowData snowData, half4 diffuse, half4 specular, half specularGloss, half3 emission, half alpha)
{
    Light mainLight = GetMainLight(inputData.shadowCoord);
    MixRealtimeAndBakedGI(mainLight, snowData.diffuseNormal, inputData.bakedGI, half4(0, 0, 0, 0));

    half3 attenuatedLightColor = mainLight.color * (mainLight.distanceAttenuation * mainLight.shadowAttenuation);
    
    half3 diffuseColor = inputData.bakedGI + LightingLambert(attenuatedLightColor, mainLight.direction, snowData.diffuseNormal);
    half3 specularColor = LightingSpecular(attenuatedLightColor, mainLight.direction, snowData.specularNormal, inputData.viewDirectionWS, specular, specularGloss);

#ifdef _ADDITIONAL_LIGHTS
    uint pixelLightCount = GetAdditionalLightsCount();
    for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
    {
        Light light = GetAdditionalLight(lightIndex, inputData.positionWS);
        half3 attenuatedLightColor = light.color * (light.distanceAttenuation * light.shadowAttenuation);
        diffuseColor += LightingLambert(attenuatedLightColor, light.direction, snowData.diffuseNormal);
        specularColor += LightingSpecular(attenuatedLightColor, light.direction, snowData.specularNormal, inputData.viewDirectionWS, specular, specularGloss);
    }
#endif

#ifdef _ADDITIONAL_LIGHTS_VERTEX
    diffuseColor += inputData.vertexLighting;
#endif

    half3 finalColor = diffuseColor * diffuse.rgb + emission;

//#if defined(_SPECGLOSSMAP) || defined(_SPECULAR_COLOR)
    finalColor += specularColor * specular.rgb * specular.a;
//#endif

    return half4(finalColor, alpha);
}

// Fragment Shader
half4 SnowFrag(Varyings input) : SV_Target {
    UNITY_SETUP_INSTANCE_ID(input);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    SnowData snowData;
    InitializeSnowData(input, snowData);
    
    SurfaceData surfaceData;
    InitializeStandardLitSurfaceData(input.uv, surfaceData);
    
    InputData inputData;
    InitializeInputData(input, surfaceData.normalTS, inputData);

    // BlinnPhong
    half4 diffuse = half4(lerp(surfaceData.albedo, _DiffuseColor.rgb, snowData.fp * _DiffuseColor.a), 1);
    half4 specular = half4(lerp(surfaceData.specular, _SpecularColor.rgb, snowData.fp * _SpecularColor.a), 1);
    half gloss = lerp(surfaceData.smoothness, _SnowSpecularGloss, snowData.fp);
    half4 color = SnowFragmentBlinnPhong(inputData, snowData, diffuse, specular, gloss, surfaceData.emission, surfaceData.alpha);
    
    color.rgb = MixFog(color.rgb, inputData.fogCoord);
    color.a = OutputAlpha(color.a);
    
    return color;
}

#endif