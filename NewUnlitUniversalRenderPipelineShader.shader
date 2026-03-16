Shader "Custom/InkTest"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1,1,1,1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}

        [Header(Ink Shading)]
        _InkLevels("Ink Levels", Range(2, 8)) = 4
        _InkSmoothness("Ink Smoothness", Range(0, 0.2)) = 0.05
        _InkDarkest("Darkest Ink", Color) = (0.1, 0.1, 0.15, 1)
        _InkLightest("Lightest Ink", Color) = (0.9, 0.9, 0.95, 1)

        [Header(Outline Effect)]
        _EdgeThreshold("Edge Threshold (bigger = thinner)", Range(0,1)) = 0.35
        _EdgeSmooth("Edge Smooth", Range(0.0001, 0.3)) = 0.05
        _EdgePower("Edge Power", Range(0.1, 8)) = 2
        _EdgeIntensity("Edge Intensity", Range(0,1)) = 1
        _EdgeColor("Edge Color", Color) = (0,0,0,1)

        [Header(Noise Corrosion)]
        _NoiseMap("Noise Texture", 2D) = "white" {}
        _CorrosionStrength("Corrosion Strength", Range(0, 1)) = 0.3
        _CorrosionScale("Corrosion Scale", Range(0.1, 10)) = 2
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 normalWS    : TEXCOORD1;
                float3 viewDirWS   : TEXCOORD2;
                float3 positionWS  : TEXCOORD3;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NoiseMap);
            SAMPLER(sampler_NoiseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;

                // Ink Shading
                float _InkLevels;
                float _InkSmoothness;
                half4 _InkDarkest;
                half4 _InkLightest;

                // Outline
                float _EdgeThreshold;
                float _EdgeSmooth;
                float _EdgePower;
                float _EdgeIntensity;
                half4 _EdgeColor;

                // Noise Corrosion
                float4 _NoiseMap_ST;
                float _CorrosionStrength;
                float _CorrosionScale;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);

                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.normalWS = normalize(TransformObjectToWorldNormal(IN.normalOS));
                OUT.viewDirWS = normalize(GetWorldSpaceViewDir(OUT.positionWS));

                return OUT;
            }

            // Quantize lighting into discrete ink levels
            float QuantizeInk(float value, float levels, float smoothness)
            {
                float step = 1.0 / levels;
                float quantized = floor(value / step) * step;
     
                // Add smooth transition between levels
                float nextLevel = quantized + step;
                float t = smoothstep(quantized + step * (1.0 - smoothness), 
                                     quantized + step * (1.0 + smoothness), 
                                     value);
       
                return lerp(quantized, nextLevel, t);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // Sample base texture
                float3 baseCol = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv).rgb * _BaseColor.rgb;

                // Get main light
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                float3 lightDir = normalize(mainLight.direction);
                float3 normalWS = normalize(IN.normalWS);

                // === INK SHADING ===
                // Calculate NdotL
                float ndotl = dot(normalWS, lightDir);
                ndotl = ndotl * 0.5 + 0.5; // Remap from [-1,1] to [0,1]
     
                // Apply shadows
                ndotl *= mainLight.shadowAttenuation;

                // Quantize into discrete ink levels
                float inkValue = QuantizeInk(ndotl, _InkLevels, _InkSmoothness);

                // Map to ink colors
                float3 inkColor = lerp(_InkDarkest.rgb, _InkLightest.rgb, inkValue);
        
                // Convert base color to grayscale and multiply with ink
                float luminance = dot(baseCol, float3(0.299, 0.587, 0.114));
                float3 inkShaded = inkColor * luminance;

                // === OUTLINE EFFECT WITH NOISE CORROSION ===
                float3 viewDirWS = normalize(IN.viewDirWS);
   
                // Calculate rim/edge factor
                float ndotv = saturate(dot(normalWS, viewDirWS));
                float edge = pow(1.0 - ndotv, _EdgePower);

                // Sample noise texture with scaled UVs
                float2 noiseUV = IN.uv * _CorrosionScale;
                float noise = SAMPLE_TEXTURE2D(_NoiseMap, sampler_NoiseMap, noiseUV).r;

                // Apply noise corrosion to edge threshold
                float corrodedThreshold = _EdgeThreshold + (noise - 0.5) * _CorrosionStrength;
 
                // Create edge mask with corroded threshold
                float edgeMask = smoothstep(corrodedThreshold, corrodedThreshold + _EdgeSmooth, edge);
                edgeMask *= _EdgeIntensity;

                // === FINAL COMPOSITION ===
                float3 outCol = lerp(inkShaded, _EdgeColor.rgb, saturate(edgeMask));
        
                return half4(outCol, 1);
            }
            ENDHLSL
        }

        // Shadow caster pass for proper shadow receiving
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }

            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        // Depth pass
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }

            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
    }
}