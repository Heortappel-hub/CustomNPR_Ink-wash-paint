Shader "ChinesePainting/MountainShaderSimpleURP_v2"
{
    // ==========================================
    // URP 移植版 v2: 借鉴 CIPR 双层描边 + 世界空间三平面 UV
    // 与 v1 (单层合并描边) 的差异:
    //   - 描边拆回双层, 用 ShaderLab Offset 让第二层只画外轮廓
    //   - 噪声 UV 从 mesh UV 改为世界空间三平面投影, 避免 shower-door 漂移
    //   - 第二层描边用自定义 LightMode "ChineseInkOutline",
    //     需通过 ScriptableRendererFeature + RenderObjects 注入才会被渲染
    //     (留作未来工作; 当前仅 Pass 0 的 SRPDefaultUnlit 自动渲染)
    // ==========================================
    Properties
    {
        [Header(OutLine)]
        _StrokeColor ("Stroke Color", Color) = (0,0,0,1)
        _OutlineNoise ("Outline Noise Map", 2D) = "white" {}
        _Outline ("Outline Width", Range(0, 0.5)) = 0.05
        _OutsideNoiseWidth ("Flying White Width", Range(1, 2)) = 1.3
        _FlyingWhiteThreshold ("Flying White Threshold", Range(0, 1)) = 0.5

        [Header(Outline World Space UV)]
        _OutlineNoiseScale ("Outline Noise World Scale", Range(0.01, 5)) = 1.0
        _OutlineNoiseScaleOuter ("Outline Noise World Scale (Outer)", Range(0.01, 5)) = 0.7

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

        [Header(Rim Light)]
        [Toggle] _UseRimLight ("Use Rim Light", Float) = 0
        _RimColor ("Rim Color", Color) = (0,1,1,1)
        _RimRate ("Rim Rate (Power)", Range(0.1, 8)) = 1.0
        _RimIntensity ("Rim Intensity", Range(0, 2)) = 1.0
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
        // 共享区: include + CBUFFER + 贴图声明
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
            float  _OutlineNoiseScale;
            float  _OutlineNoiseScaleOuter;
            float  _InteriorNoiseLevel;
            float  _KuwaharaSize;
            float  _BlurRadius;
            float  _Resolution;
            float  _HStep;
            float  _VStep;
            float4 _RimColor;
            float  _RimRate;
            float  _RimIntensity;
        CBUFFER_END

        TEXTURE2D(_OutlineNoise);  SAMPLER(sampler_OutlineNoise);
        TEXTURE2D(_Ramp);          SAMPLER(sampler_Ramp);
        TEXTURE2D(_StrokeTex);     SAMPLER(sampler_StrokeTex);
        TEXTURE2D(_InteriorNoise); SAMPLER(sampler_InteriorNoise);

        // 世界空间三平面 UV: 把世界坐标三个轴向投影叠加
        // 优点: 1) 不依赖 mesh UV 展开 2) 噪声锚定世界空间, 相机移动不漂移
        float2 TriplanarUV(float3 worldPos, float scale)
        {
            return (worldPos.xy + worldPos.yz + worldPos.xz) * scale;
        }
        ENDHLSL

        // ==========================================
        // Pass 0: 内层描边 (基础轮廓)
        // LightMode = SRPDefaultUnlit, URP 默认渲染器自动调用
        // 在所有轮廓位置画粗笔触, 包括外轮廓与内部褶皱
        // ==========================================
        Pass
        {
            NAME "OUTLINE_INNER"
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
                float2 noiseUV : TEXCOORD0;
            };

            Varyings vert (Attributes v)
            {
                Varyings o;

                // 世界空间三平面 UV 用于噪声采样 (避免相机移动时噪声漂移)
                float3 worldPos = TransformObjectToWorld(v.vertex.xyz);
                o.noiseUV = TriplanarUV(worldPos, _OutlineNoiseScale);

                // 顶点采样噪声调制描边宽度, 让边线粗细不规则
                float4 vNoise = SAMPLE_TEXTURE2D_LOD(_OutlineNoise, sampler_OutlineNoise, o.noiseUV, 0);

                // 模型空间法线膨胀: 基础描边宽度
                float3 normal = normalize(v.normal);
                float outlineWidth = _Outline * (0.5 + vNoise.g * 0.5);

                float3 offsetPos = v.vertex.xyz + normal * outlineWidth;
                o.pos = TransformObjectToHClip(offsetPos);

                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // 内层描边不做飞白 (留给外层处理), 保证内部褶皱有完整笔触
                return _StrokeColor;
            }
            ENDHLSL
        }

        // ==========================================
        // Pass 1: 外层描边 (飞白 + 仅外轮廓)
        // 关键设计: Offset 20,0 把片元深度推远, 使其
        //   - 在外轮廓 (背景边) 处通过深度测试可见
        //   - 在内部褶皱处被正常物体遮挡, 自然只画外轮廓
        // 这是 CIPR 方案的核心思想, 用深度偏移区分内外描边
        //
        // LightMode = UniversalForwardOnly: URP Forward 渲染器
        // 会在不透明阶段自动调用此 tag 的 Pass, 实现多 Pass 描边
        // (与 Pass 2 的 UniversalForward / Pass 0 的 SRPDefaultUnlit 互不冲突)
        // ==========================================
        Pass
        {
            NAME "OUTLINE_OUTER"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull Front
            Offset 20, 0

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
                float2 noiseUV : TEXCOORD0;
            };

            Varyings vert (Attributes v)
            {
                Varyings o;

                // 外层描边使用不同 scale 的三平面 UV,
                // 与内层错开频率, 避免叠加位置完全重合
                float3 worldPos = TransformObjectToWorld(v.vertex.xyz);
                o.noiseUV = TriplanarUV(worldPos, _OutlineNoiseScaleOuter);

                float4 vNoise = SAMPLE_TEXTURE2D_LOD(_OutlineNoise, sampler_OutlineNoise, o.noiseUV, 0);

                // 外层膨胀宽度更大 (基础宽度 * 飞白宽度倍率)
                float3 normal = normalize(v.normal);
                float outlineWidth = _Outline * _OutsideNoiseWidth * (0.5 + vNoise.g * 0.5);

                float3 offsetPos = v.vertex.xyz + normal * outlineWidth;
                o.pos = TransformObjectToHClip(offsetPos);

                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                // 飞白: 噪声值高于阈值的像素直接 discard 制造断笔
                half noise = SAMPLE_TEXTURE2D(_OutlineNoise, sampler_OutlineNoise, i.noiseUV).r;
                clip(noise - _FlyingWhiteThreshold);

                return _StrokeColor;
            }
            ENDHLSL
        }

        // ==========================================
        // Pass 2: 内部填充
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
            #pragma shader_feature_local _USERIMLIGHT_ON

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
                o.uv2    = TRANSFORM_TEX(v.texcoord, _StrokeTex);
                o.worldNormal = TransformObjectToWorldNormal(v.normal);
                o.worldPos    = TransformObjectToWorld(v.vertex.xyz);
                o.shadowCoord = TransformWorldToShadowCoord(o.worldPos);
                return o;
            }

    half4 frag(Varyings i) : SV_Target
    {
 half3 worldNormal = normalize(i.worldNormal);

       Light mainLight = GetMainLight(i.shadowCoord);
  half3 worldLightDir = normalize(mainLight.direction);

            half4 burn = SAMPLE_TEXTURE2D(_InteriorNoise, sampler_InteriorNoise, i.uv);

          // 半兰伯特光照
         half diff = dot(worldNormal, worldLightDir);
  diff = (diff * 0.5 + 0.5);

// 笔触噪声偏移 Ramp UV
float2 k = SAMPLE_TEXTURE2D(_StrokeTex, sampler_StrokeTex, i.uv).xy;
         float2 cuv = float2(diff, diff) + k * burn.xy * _InteriorNoiseLevel;
          cuv = clamp(cuv, 0.01, 0.99);

                float3 finalColor;

  #ifdef _USEKUWAHARA_ON
        finalColor = KuwaharaFilter(TEXTURE2D_ARGS(_Ramp, sampler_Ramp), cuv);
     #else
         finalColor = GaussianBlur(TEXTURE2D_ARGS(_Ramp, sampler_Ramp), cuv);
         #endif

        // Rim Light: 边缘高光, 与视线方向夹角大处亮
                #ifdef _USERIMLIGHT_ON
         half3 worldViewDir = normalize(GetWorldSpaceViewDir(i.worldPos));
            half rim = 1.0 - saturate(dot(worldViewDir, worldNormal));
    rim = pow(saturate(rim), _RimRate) * _RimIntensity;
       finalColor = lerp(finalColor, _RimColor.rgb, saturate(rim));
 #endif

          return half4(finalColor, 1.0);
            }
       ENDHLSL
        }

        // ==========================================
        // Pass 3: ShadowCaster
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
        // Pass 4: DepthOnly
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

