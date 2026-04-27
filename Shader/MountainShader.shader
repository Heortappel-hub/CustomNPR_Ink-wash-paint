
// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "ChinesePainting/MountainShader" 
{
	Properties 
	{
		[Header(OutLine)]
		_StrokeColor ("Stroke Color", Color) = (0,0,0,1)
		_OutlineNoise ("Outline Noise Map", 2D) = "white" {}
		_Outline ("Outline", Range(0, 1)) = 0.1
		_OutsideNoiseWidth ("Outside Noise Width", Range(1, 2)) = 1.3
		_MaxOutlineZOffset ("Max Outline Z Offset", Range(0,1)) = 0.5

		[Header(Interior)]
		_Ramp ("Ramp Texture", 2D) = "white" {}
		_StrokeTex ("Stroke Noise Tex", 2D) = "white" {}
		_InteriorNoiseLevel ("Interior Noise Level", Range(0, 1)) = 0.15
		
		[Header(Blur Settings)]
		_BlurAmount ("Blur Amount (Mipmap)", Range(0, 8)) = 2.0
		
		[Header(Procedural Noise)]
		_NoiseScale ("Noise Scale", Range(1, 50)) = 10.0
		_NoiseStrength ("Noise Strength", Range(0, 1)) = 0.5
		[Toggle(_USEPROCEDURALNOISE_ON)] _UseProceduralNoise ("Use Procedural Noise", Float) = 0
	}
	
    SubShader 
	{
		Tags 
		{ 
			"RenderType" = "Opaque" 
			"Queue" = "Geometry"
			"RenderPipeline" = "UniversalPipeline"
		}

		// ============================================
		// 共享代码 (HLSLINCLUDE)
		// ============================================
		HLSLINCLUDE
		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
		
		// 材质属性 CBUFFER
		CBUFFER_START(UnityPerMaterial)
			float4 _StrokeColor;
			float4 _OutlineNoise_ST;
			float4 _Ramp_ST;
			float4 _StrokeTex_ST;
			float _Outline;
			float _OutsideNoiseWidth;
			float _MaxOutlineZOffset;
			float _InteriorNoiseLevel;
			float _BlurAmount;
			float _NoiseScale;
			float _NoiseStrength;
		CBUFFER_END
		
		// 纹理声明
		TEXTURE2D(_OutlineNoise);
		SAMPLER(sampler_OutlineNoise);
		TEXTURE2D(_Ramp);
		SAMPLER(sampler_Ramp);
		TEXTURE2D(_StrokeTex);
		SAMPLER(sampler_StrokeTex);
		
		// Hash 函数 - 快速伪随机
		float hash(float2 p)
		{
			float3 p3 = frac(float3(p.xyx) * 0.1031);
			p3 += dot(p3, p3.yzx + 33.33);
			return frac((p3.x + p3.y) * p3.z);
		}
		
		// Value Noise
		float valueNoise(float2 p)
		{
			float2 i = floor(p);
			float2 f = frac(p);
			
			float a = hash(i);
			float b = hash(i + float2(1.0, 0.0));
			float c = hash(i + float2(0.0, 1.0));
			float d = hash(i + float2(1.0, 1.0));
			
			float2 u = f * f * (3.0 - 2.0 * f);
			
			return lerp(lerp(a, b, u.x), lerp(c, d, u.x), u.y);
		}
		
		// FBM (分形布朗运动)
		float fbm(float2 p, int octaves)
		{
			float value = 0.0;
			float amplitude = 0.5;
			float frequency = 1.0;
			
			for (int i = 0; i < octaves; i++)
			{
				value += amplitude * valueNoise(p * frequency);
				amplitude *= 0.5;
				frequency *= 2.0;
			}
			return value;
		}
		
		ENDHLSL

		// ============================================
		// Pass 1: OUTLINE (基础描边)
		// ============================================
		Pass 
		{
			Name "OUTLINE"
			Tags { "LightMode" = "SRPDefaultUnlit" }
			Cull Front
			
			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma shader_feature_local _USEPROCEDURALNOISE_ON

			struct Attributes
			{
				float4 positionOS : POSITION;
				float3 normalOS : NORMAL;
				float2 uv : TEXCOORD0;
			}; 
			
			struct Varyings
			{
			    float4 positionCS : SV_POSITION;
			};
			
			Varyings vert(Attributes input) 
			{
				Varyings output = (Varyings)0;
				
				// 噪声采样
				float noiseValue;
				#ifdef _USEPROCEDURALNOISE_ON
					noiseValue = fbm(input.uv * _NoiseScale, 3) * _NoiseStrength + (1.0 - _NoiseStrength) * 0.5;
				#else
					float2 noiseUV = TRANSFORM_TEX(input.uv, _OutlineNoise);
					noiseValue = SAMPLE_TEXTURE2D_LOD(_OutlineNoise, sampler_OutlineNoise, noiseUV, 0).x;
				#endif

				// View space 计算
				float3 normalVS = mul((float3x3)UNITY_MATRIX_MV, input.normalOS);
				normalVS += 0.5;
				normalVS.z = 0.01;
				normalVS = normalize(normalVS);

				float4 positionVS = mul(UNITY_MATRIX_MV, input.positionOS);
				positionVS /= positionVS.w;

				float3 viewDir = normalize(positionVS.xyz);
				float3 offsetPosVS = positionVS.xyz + viewDir * _MaxOutlineZOffset;
  
				// 透视校正的线宽
				float linewidth = sqrt(-positionVS.z / unity_CameraProjection[1].y);
				positionVS.xy = offsetPosVS.xy + normalVS.xy * linewidth * noiseValue * _Outline;
				positionVS.z = offsetPosVS.z;

				output.positionCS = mul(UNITY_MATRIX_P, positionVS);
				return output;
			}
			
			half4 frag(Varyings input) : SV_Target 
			{
				return _StrokeColor;
			}
			ENDHLSL
		}
		
		// ============================================
		// Pass 2: OUTLINE 2 (飞白描边)
		// ============================================
		Pass 
		{
			Name "OUTLINE2"
			Tags { "LightMode" = "UniversalForwardOnly" }
			Cull Front
			
			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma shader_feature_local _USEPROCEDURALNOISE_ON

			struct Attributes
			{
				float4 positionOS : POSITION;
				float3 normalOS : NORMAL;
				float2 uv : TEXCOORD0;
			}; 
			
			struct Varyings
			{
			    float4 positionCS : SV_POSITION;
				float2 uv : TEXCOORD0;
			};
			
			Varyings vert(Attributes input) 
			{
				Varyings output = (Varyings)0;
				
				float noiseValue;
				#ifdef _USEPROCEDURALNOISE_ON
					noiseValue = fbm(input.uv * _NoiseScale * 1.3, 3) * _NoiseStrength + (1.0 - _NoiseStrength) * 0.5;
				#else
					float2 noiseUV = TRANSFORM_TEX(input.uv, _OutlineNoise);
					noiseValue = SAMPLE_TEXTURE2D_LOD(_OutlineNoise, sampler_OutlineNoise, noiseUV, 0).y;
				#endif

				float3 normalVS = mul((float3x3)UNITY_MATRIX_MV, input.normalOS);
				normalVS += 0.5;
				normalVS.z = 0.01;
				normalVS = normalize(normalVS);

				float4 positionVS = mul(UNITY_MATRIX_MV, input.positionOS);
				positionVS /= positionVS.w;

				float3 viewDir = normalize(positionVS.xyz);
				float3 offsetPosVS = positionVS.xyz + viewDir * _MaxOutlineZOffset;

				float linewidth = sqrt(-positionVS.z / unity_CameraProjection[1].y);
				positionVS.xy = offsetPosVS.xy + normalVS.xy * linewidth * noiseValue * _Outline * 1.1 * _OutsideNoiseWidth;
				positionVS.z = offsetPosVS.z;

				output.positionCS = mul(UNITY_MATRIX_P, positionVS);
				output.uv = input.uv;
				return output;
			}
			
			half4 frag(Varyings input) : SV_Target 
			{
				float clipValue;
				#ifdef _USEPROCEDURALNOISE_ON
					clipValue = fbm(input.uv * _NoiseScale * 2.0, 2);
				#else
					clipValue = SAMPLE_TEXTURE2D(_OutlineNoise, sampler_OutlineNoise, input.uv).x;
				#endif
				
				clip(0.5 - clipValue);
				return _StrokeColor;
			}
			ENDHLSL
		}
		
		// ============================================
		// Pass 3: INTERIOR (内部着色)
		// ============================================
		Pass 
		{
			Name "INTERIOR"
			Tags { "LightMode" = "UniversalForward" }
			Cull Back
			
			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma shader_feature_local _USEPROCEDURALNOISE_ON
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
			#pragma multi_compile _ _SHADOWS_SOFT

			struct Attributes
			{
				float4 positionOS : POSITION;
				float3 normalOS : NORMAL;
				float2 uv : TEXCOORD0;
			}; 
		
			struct Varyings
			{
				float4 positionCS : SV_POSITION;
				float2 uv : TEXCOORD0;
				float3 normalWS : TEXCOORD1;
				float3 positionWS : TEXCOORD2;
			};

			Varyings vert(Attributes input) 
			{
				Varyings output;
				
				VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
				VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS);
				
				output.positionCS = vertexInput.positionCS;
				output.positionWS = vertexInput.positionWS;
				output.normalWS = normalInput.normalWS;
				output.uv = TRANSFORM_TEX(input.uv, _Ramp);
				
				return output;
			}
			
			half4 frag(Varyings input) : SV_Target 
			{ 
				// 获取主光源
				Light mainLight = GetMainLight();
				float3 lightDir = normalize(mainLight.direction);
				float3 normalWS = normalize(input.normalWS);

				// 噪声扰动
				float2 noise;
				#ifdef _USEPROCEDURALNOISE_ON
					noise.x = fbm(input.uv * _NoiseScale, 2);
					noise.y = fbm(input.uv * _NoiseScale + 100.0, 2);
				#else
					noise = SAMPLE_TEXTURE2D(_StrokeTex, sampler_StrokeTex, input.uv).xy;
				#endif
				
				// Half Lambert
				float diff = dot(normalWS, lightDir) * 0.5 + 0.5;
				float2 cuv = float2(diff, diff) + noise * _InteriorNoiseLevel;

				// 无分支 clamp
				cuv = saturate(cuv);
				float mask = step(0.95, max(cuv.x, cuv.y));
				cuv = lerp(cuv, float2(0.95, 1.0), mask);

				// Mipmap 模糊
				half4 color = SAMPLE_TEXTURE2D_LOD(_Ramp, sampler_Ramp, cuv, _BlurAmount);

				return half4(color.rgb, 1.0);
			}
			ENDHLSL
		}
	}
	
	FallBack "Universal Render Pipeline/Lit"
}
