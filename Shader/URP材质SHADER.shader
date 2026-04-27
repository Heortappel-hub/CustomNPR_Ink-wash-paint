Shader "ChinesePainting/MountainShaderSimpleURP"
{
    // ==========================================
    // URP 移植版本: 基于过程几何法的描边 (Object-Space Outline)
    // 与 Built-in 版本对照说明:
    //   - Built-in 三个 Pass (基础描边 + 飞白描边 + 内部填充)
    //   - URP 移植版合并描边 Pass, 因 URP 默认仅渲染单个 SRPDefaultUnlit
    //   - 额外补充 ShadowCaster / DepthOnly Pass 以兼容 URP 阴影与深度
    // ==========================================
    Properties
    {
        [Header(OutLine)]
        _StrokeColor ("Stroke Color", Color) = (0,0,0,1)
        _OutlineNoise ("Outline Noise Map", 2D) = "white" {}
        _Outline ("Outline Width", Range(0, 0.5)) = 0.05
        _OutsideNoiseWidth ("Flying White Width", Range(1, 2)) = 1.3
        _FlyingWhiteThreshold ("Flying White Threshold", Range(0, 1)) = 0.5

        [Header(Interior)]
        _Ramp ("Ramp Texture", 2D) = "white" {}
        _StrokeTex ("Stroke Noise Tex", 2D) = "white" {}
        _InteriorNoise ("Interior Noise Map", 2D) = "white" {}
        _InteriorNoiseLevel ("Interior Noise Level", Range(0, 1)) = 0.15

        [Header(Filter Settings)]
        [Toggle] _UseKuwahara ("Use Kuwahara Filter", Float) = 0
        _KuwaharaSize ("Kuwahara Size", Range(0.001, 0.1)) = 0.02
        _BlurRadius ("Gaussian Blur Radius", Range(0, 60)) = 30
        _Resolution ("Resolution", Float) = 800
        _HStep ("Horizontal Step", Range(0, 1)) = 0.5
        _VStep ("Vertical Step", Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "Queue"="Geometry"
            "RenderPipeline"="UniversalPipeline"
        }

        // ==========================================
        // 全 Pass 共享区: include + CBUFFER + 贴图声明
        // CBUFFER_START(UnityPerMaterial) 是 SRP Batcher 兼容的关键
        // 所有 per-material uniform 必须放在这一个块里
        // ==========================================
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _OutlineNoise_ST;
            float4 _Ramp_ST;
            float4 _StrokeTex_ST;
            float4 _StrokeColor;
            float  _Outline;
            float  _OutsideNoiseWidth;
            float  _FlyingWhiteThreshold;
            float  _InteriorNoiseLevel;
            float  _KuwaharaSize;
            float  _BlurRadius;
            float  _Resolution;
            float  _HStep;
            float  _VStep;
        CBUFFER_END

        TEXTURE2D(_OutlineNoise);  SAMPLER(sampler_OutlineNoise);
        TEXTURE2D(_Ramp);          SAMPLER(sampler_Ramp);
        TEXTURE2D(_StrokeTex);     SAMPLER(sampler_StrokeTex);
        TEXTURE2D(_InteriorNoise); SAMPLER(sampler_InteriorNoise);
        ENDHLSL

        // ==========================================
        // Pass 0: 描边 + 飞白 (合并版)
        // LightMode = SRPDefaultUnlit, URP 默认渲染器会自动调用
        // 沿模型空间法线膨胀几何 + 噪声 discard 模拟飞白
        // ==========================================
        Pass
        {
            NAME "OUTLINE"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes
            {
                float4 vertex   : POSITION;
                float3 normal   : NORMAL;
                float2 texcoord : TEXCOORD0;
            };

            struct Varyings
            {
                float4 pos : SV_POSITION;
                float2 uv  : TEXCOORD0;
            };

            Varyings vert (Attributes v)
            {
                Varyings o;

                // 采样噪声调制描边宽度, 让边线粗细不规则
                float2 noiseUV = v.texcoord * _OutlineNoise_ST.xy + _OutlineNoise_ST.zw;
                float4 noise = SAMPLE_TEXTURE2D_LOD(_OutlineNoise, sampler_OutlineNoise, noiseUV, 0);

                // 模型空间法线膨胀
                // 原 Built-in 是两层 Pass 叠加 (内层 _Outline, 外层 _Outline*_OutsideNoiseWidth)
                // URP 单 Pass 取最大膨胀, 视觉效果近似但缺少双层叠加层次
                float3 normal = normalize(v.normal);
                float outlineWidth = _Outline * _OutsideNoiseWidth * (0.5 + noise.g * 0.5);

                float3 offsetPos = v.vertex.xyz + normal * outlineWidth;
                o.pos = TransformObjectToHClip(offsetPos);
                o.uv  = v.texcoord;

                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // 飞白: 噪声值高于阈值的像素直接 discard 制造断笔效果
                half noise = SAMPLE_TEXTURE2D(_OutlineNoise, sampler_OutlineNoise, i.uv).r;
                if (noise > _FlyingWhiteThreshold)
                    discard;

                return _StrokeColor;
            }
            ENDHLSL
        }

        // ==========================================
        // Pass 1: 内部填充
        // LightMode = UniversalForward, URP 主前向渲染入口
        // 半兰伯特 Ramp 光照 + 高斯模糊 / Kuwahara 滤波二选一
        // ==========================================
        Pass
        {
            NAME "INTERIOR"
            Tags { "LightMode"="UniversalForward" }
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local _USEKUWAHARA_ON

            // URP 主光源 / 阴影 keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 vertex   : POSITION;
                float3 normal   : NORMAL;
                float4 texcoord : TEXCOORD0;
            };

            struct Varyings
            {
                float4 pos         : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 worldNormal : TEXCOORD1;
                float3 worldPos    : TEXCOORD2;
                float2 uv2         : TEXCOORD3;
                float4 shadowCoord : TEXCOORD4;
            };

            // ====== Kuwahara 辅助函数: 计算单个象限的均值与方差 ======
            void CalcQuadrant(TEXTURE2D_PARAM(tex, samp), float2 uv, float2 offsetDir, float size,
                              out float3 mean, out float variance)
            {
                float3 sum   = float3(0, 0, 0);
                float3 sqSum = float3(0, 0, 0);

                for (int x = 0; x <= 2; x++)
                {
                    for (int y = 0; y <= 2; y++)
                    {
                        float2 offset = (float2(x, y) * offsetDir) * size;
                        float2 sampleUV = clamp(uv + offset, 0.01, 0.99);
                        float3 c = SAMPLE_TEXTURE2D(tex, samp, sampleUV).rgb;
                        sum   += c;
                        sqSum += c * c;
                    }
                }

                mean = sum / 9.0;
                sqSum /= 9.0;
                float3 var = sqSum - mean * mean;
                variance = var.r + var.g + var.b;
            }

            // ====== 9 抽样高斯模糊 ======
            float3 GaussianBlur(TEXTURE2D_PARAM(tex, samp), float2 uv)
            {
                float4 sum = float4(0, 0, 0, 0);
                float blur = _BlurRadius / _Resolution / 4.0;

                sum += SAMPLE_TEXTURE2D(tex, samp, float2(uv.x - 4.0*blur*_HStep, uv.y - 4.0*blur*_VStep)) * 0.0162162162;
                sum += SAMPLE_TEXTURE2D(tex, samp, float2(uv.x - 3.0*blur*_HStep, uv.y - 3.0*blur*_VStep)) * 0.0540540541;
                sum += SAMPLE_TEXTURE2D(tex, samp, float2(uv.x - 2.0*blur*_HStep, uv.y - 2.0*blur*_VStep)) * 0.1216216216;
                sum += SAMPLE_TEXTURE2D(tex, samp, float2(uv.x - 1.0*blur*_HStep, uv.y - 1.0*blur*_VStep)) * 0.1945945946;
                sum += SAMPLE_TEXTURE2D(tex, samp, float2(uv.x, uv.y))                                       * 0.2270270270;
                sum += SAMPLE_TEXTURE2D(tex, samp, float2(uv.x + 1.0*blur*_HStep, uv.y + 1.0*blur*_VStep)) * 0.1945945946;
                sum += SAMPLE_TEXTURE2D(tex, samp, float2(uv.x + 2.0*blur*_HStep, uv.y + 2.0*blur*_VStep)) * 0.1216216216;
                sum += SAMPLE_TEXTURE2D(tex, samp, float2(uv.x + 3.0*blur*_HStep, uv.y + 3.0*blur*_VStep)) * 0.0540540541;
                sum += SAMPLE_TEXTURE2D(tex, samp, float2(uv.x + 4.0*blur*_HStep, uv.y + 4.0*blur*_VStep)) * 0.0162162162;

                return sum.rgb;
            }

            // ====== Kuwahara 滤波: 选择四个象限中方差最小者的均值 ======
            float3 KuwaharaFilter(TEXTURE2D_PARAM(tex, samp), float2 uv)
            {
                float3 mean0, mean1, mean2, mean3;
                float  var0,  var1,  var2,  var3;
                float  size = _KuwaharaSize;

                CalcQuadrant(TEXTURE2D_ARGS(tex, samp), uv, float2(-1,  1), size, mean0, var0);
                CalcQuadrant(TEXTURE2D_ARGS(tex, samp), uv, float2( 1,  1), size, mean1, var1);
                CalcQuadrant(TEXTURE2D_ARGS(tex, samp), uv, float2(-1, -1), size, mean2, var2);
                CalcQuadrant(TEXTURE2D_ARGS(tex, samp), uv, float2( 1, -1), size, mean3, var3);

                float3 finalColor = mean0;
                float  minVar     = var0;

                if (var1 < minVar) { finalColor = mean1; minVar = var1; }
                if (var2 < minVar) { finalColor = mean2; minVar = var2; }
                if (var3 < minVar) { finalColor = mean3; }

                return finalColor;
            }

            Varyings vert (Attributes v)
            {
                Varyings o;
                o.pos         = TransformObjectToHClip(v.vertex.xyz);
                o.uv          = TRANSFORM_TEX(v.texcoord, _Ramp);
                o.uv2         = TRANSFORM_TEX(v.texcoord, _StrokeTex);
                o.worldNormal = TransformObjectToWorldNormal(v.normal);
                o.worldPos    = TransformObjectToWorld(v.vertex.xyz);
                o.shadowCoord = TransformWorldToShadowCoord(o.worldPos);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                half3 worldNormal = normalize(i.worldNormal);

                // URP 主光源获取 (含阴影衰减)
                Light mainLight = GetMainLight(i.shadowCoord);
                half3 worldLightDir = normalize(mainLight.direction);

                half4 burn = SAMPLE_TEXTURE2D(_InteriorNoise, sampler_InteriorNoise, i.uv);

                // 半兰伯特光照
                half diff = dot(worldNormal, worldLightDir);
                diff = (diff * 0.5 + 0.5);

                // 笔触噪声偏移 Ramp UV, 制造水墨笔触感
                float2 k = SAMPLE_TEXTURE2D(_StrokeTex, sampler_StrokeTex, i.uv).xy;
                float2 cuv = float2(diff, diff) + k * burn.xy * _InteriorNoiseLevel;
                cuv = clamp(cuv, 0.01, 0.99);

                float3 finalColor;

                #ifdef _USEKUWAHARA_ON
                    finalColor = KuwaharaFilter(TEXTURE2D_ARGS(_Ramp, sampler_Ramp), cuv);
                #else
                    finalColor = GaussianBlur(TEXTURE2D_ARGS(_Ramp, sampler_Ramp), cuv);
                #endif

                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }

        // ==========================================
        // Pass 2: ShadowCaster (URP 阴影投射)
        // 复用 URP 内置 ShadowCasterPass.hlsl, 标准做法
        // ==========================================
        Pass
        {
            NAME "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex   ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        // ==========================================
        // Pass 3: DepthOnly (URP 深度通道)
        // 让后处理 (例如 Ink.shader) 能正确读取 _CameraDepthTexture
        // ==========================================
        Pass
        {
            NAME "DepthOnly"
            Tags { "LightMode"="DepthOnly" }

            ZWrite On
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex   DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
