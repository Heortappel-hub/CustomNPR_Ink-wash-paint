Shader "ChinesePainting/MountainShaderSimple" 
{
	// ==========================================
	// 基于过程几何方法的描边 (Object-Space Outline)
	// 相比视点方向方法，计算更简单，性能更好
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

		[Header(Rim Light)]
		[Toggle(_USERIMLIGHT_ON)] _UseRimLight ("Use Rim Light", Float) = 0
		_RimColor ("Rim Color", Color) = (0,1,1,1)
		_RimRate ("Rim Rate (Power)", Range(0.1, 8)) = 1.0
		_RimIntensity ("Rim Intensity", Range(0, 2)) = 1.0
	}
	
	SubShader 
	{
		Tags { "RenderType"="Opaque" "Queue"="Geometry"}

		// ==========================================
		// Pass 0: 基础描边 - 过程几何方法
		// 原理：在模型空间直接沿法线方向膨胀顶点
		// 优点：计算简单，性能好
		// ==========================================
		Pass 
		{
			NAME "OUTLINE_SIMPLE"
			Cull Front      // 剔除正面，只渲染背面
			
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"
			
			float _Outline;
			float4 _StrokeColor;
			sampler2D _OutlineNoise;
			float4 _OutlineNoise_ST;

			struct a2v 
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float2 texcoord : TEXCOORD0;
			}; 
			
			struct v2f 
			{
			    float4 pos : SV_POSITION;
			};
			
			v2f vert (a2v v) 
			{
				v2f o;
				
				// 采样噪声贴图，让描边不规则
				float2 noiseUV = v.texcoord * _OutlineNoise_ST.xy + _OutlineNoise_ST.zw;
				float4 noise = tex2Dlod(_OutlineNoise, float4(noiseUV, 0, 0));
				
				// ========================================
				// 核心：过程几何方法 - 在模型空间沿法线膨胀
				// ========================================
				float3 normal = normalize(v.normal);
				
				// 噪声调制描边宽度，让描边有粗细变化
				float outlineWidth = _Outline * (0.5 + noise.r * 0.5);
				
				// 直接在模型空间沿法线方向偏移顶点
				float3 offsetPos = v.vertex.xyz + normal * outlineWidth;
				
				// 转换到裁剪空间
				o.pos = UnityObjectToClipPos(float4(offsetPos, 1.0));
				
				return o;
			}
			
			fixed4 frag(v2f i) : SV_Target 
			{
				return _StrokeColor;
			}
			ENDCG
		}
		
		// ==========================================
		// Pass 1: 飞白描边 - 过程几何方法
		// 比基础描边稍宽，随机丢弃像素模拟飞白效果
		// ==========================================
		Pass 
		{
			NAME "OUTLINE_FLYING_WHITE"
			Cull Front
			
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"
			
			float _Outline;
			float4 _StrokeColor;
			sampler2D _OutlineNoise;
			float4 _OutlineNoise_ST;
			float _OutsideNoiseWidth;
			float _FlyingWhiteThreshold;

			struct a2v 
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float2 texcoord : TEXCOORD0;
			}; 
			
			struct v2f 
			{
			    float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
			};
			
			v2f vert (a2v v) 
			{
				v2f o;
				
				float2 noiseUV = v.texcoord * _OutlineNoise_ST.xy + _OutlineNoise_ST.zw;
				float4 noise = tex2Dlod(_OutlineNoise, float4(noiseUV, 0, 0));
				
				// 过程几何方法 - 模型空间沿法线膨胀
				float3 normal = normalize(v.normal);
				
				// 飞白描边比基础描边宽，使用不同的噪声通道
				float outlineWidth = _Outline * _OutsideNoiseWidth * (0.5 + noise.g * 0.5);
				
				float3 offsetPos = v.vertex.xyz + normal * outlineWidth;
				
				o.pos = UnityObjectToClipPos(float4(offsetPos, 1.0));
				o.uv = v.texcoord;
				
				return o;
			}
			
			fixed4 frag(v2f i) : SV_Target 
			{
				// 采样噪声，随机丢弃像素产生飞白效果
				fixed noise = tex2D(_OutlineNoise, i.uv).r;
				
				if (noise > _FlyingWhiteThreshold)
					discard;
					
				return _StrokeColor;
			}
			ENDCG
		}
		
		// ==========================================
		// Pass 2: 内部填充
		// 支持高斯模糊和 Kuwahara 滤波器
		// ==========================================
		Pass 
		{
			NAME "INTERIOR"
			Tags { "LightMode"="ForwardBase" }
			Cull Back
			
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fwdbase
			#pragma shader_feature _USEKUWAHARA_ON
			#pragma shader_feature _USERIMLIGHT_ON
			
			#include "UnityCG.cginc"
			#include "Lighting.cginc"
			#include "AutoLight.cginc"
			
			sampler2D _Ramp;
			float4 _Ramp_ST;
			sampler2D _StrokeTex;
			float4 _StrokeTex_ST;
			sampler2D _InteriorNoise;
			float _InteriorNoiseLevel;
			float _KuwaharaSize;
			float _BlurRadius;
			float _Resolution;
			float _HStep;
			float _VStep;
			float4 _RimColor;
			float _RimRate;
			float _RimIntensity;
			
			struct a2v 
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float4 texcoord : TEXCOORD0;
			}; 
		
			struct v2f 
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
				float3 worldNormal : TEXCOORD1;
				float3 worldPos : TEXCOORD2;
				float2 uv2 : TEXCOORD3;
				SHADOW_COORDS(4)
			};

			v2f vert (a2v v) 
			{
				v2f o;
				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv = TRANSFORM_TEX(v.texcoord, _Ramp);
				o.uv2 = TRANSFORM_TEX(v.texcoord, _StrokeTex);
				o.worldNormal = UnityObjectToWorldNormal(v.normal);
				o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
				TRANSFER_SHADOW(o);
				return o;
			}
			
			// Kuwahara 滤波器辅助函数
			void CalcQuadrant(sampler2D tex, float2 uv, float2 offsetDir, float size, 
				out float3 mean, out float variance)
			{
				float3 sum = float3(0,0,0);
				float3 sqSum = float3(0,0,0);
				
				for (int x = 0; x <= 2; x++)
				{
					for (int y = 0; y <= 2; y++)
					{
						float2 offset = (float2(x, y) * offsetDir) * size;
						float2 sampleUV = clamp(uv + offset, 0.01, 0.99);
						float3 c = tex2D(tex, sampleUV).rgb;
						sum += c;
						sqSum += c * c;
					}
				}
				
				mean = sum / 9.0;
				sqSum /= 9.0;
				float3 var = sqSum - mean * mean;
				variance = var.r + var.g + var.b;
			}
			
			// 高斯模糊函数
			float3 GaussianBlur(sampler2D tex, float2 uv)
			{
				float4 sum = float4(0, 0, 0, 0);
				float blur = _BlurRadius / _Resolution / 4;
				
				sum += tex2D(tex, float2(uv.x - 4.0*blur*_HStep, uv.y - 4.0*blur*_VStep)) * 0.0162162162;
				sum += tex2D(tex, float2(uv.x - 3.0*blur*_HStep, uv.y - 3.0*blur*_VStep)) * 0.0540540541;
				sum += tex2D(tex, float2(uv.x - 2.0*blur*_HStep, uv.y - 2.0*blur*_VStep)) * 0.1216216216;
				sum += tex2D(tex, float2(uv.x - 1.0*blur*_HStep, uv.y - 1.0*blur*_VStep)) * 0.1945945946;
				sum += tex2D(tex, float2(uv.x, uv.y)) * 0.2270270270;
				sum += tex2D(tex, float2(uv.x + 1.0*blur*_HStep, uv.y + 1.0*blur*_VStep)) * 0.1945945946;
				sum += tex2D(tex, float2(uv.x + 2.0*blur*_HStep, uv.y + 2.0*blur*_VStep)) * 0.1216216216;
				sum += tex2D(tex, float2(uv.x + 3.0*blur*_HStep, uv.y + 3.0*blur*_VStep)) * 0.0540540541;
				sum += tex2D(tex, float2(uv.x + 4.0*blur*_HStep, uv.y + 4.0*blur*_VStep)) * 0.0162162162;
				
				return sum.rgb;
			}
			
			// Kuwahara 滤波器函数
			float3 KuwaharaFilter(sampler2D tex, float2 uv)
			{
				float3 mean0, mean1, mean2, mean3;
				float var0, var1, var2, var3;
				float size = _KuwaharaSize;
				
				CalcQuadrant(tex, uv, float2(-1, 1), size, mean0, var0);
				CalcQuadrant(tex, uv, float2(1, 1), size, mean1, var1);
				CalcQuadrant(tex, uv, float2(-1, -1), size, mean2, var2);
				CalcQuadrant(tex, uv, float2(1, -1), size, mean3, var3);
				
				float3 finalColor = mean0;
				float minVar = var0;
				
				if (var1 < minVar) { finalColor = mean1; minVar = var1; }
				if (var2 < minVar) { finalColor = mean2; minVar = var2; }
				if (var3 < minVar) { finalColor = mean3; }
				
				return finalColor;
			}
			
			float4 frag(v2f i) : SV_Target 
			{ 
				fixed3 worldNormal = normalize(i.worldNormal);
				fixed3 worldLightDir = normalize(UnityWorldSpaceLightDir(i.worldPos));
				float4 burn = tex2D(_InteriorNoise, i.uv);
				
				// 半兰伯特光照
				fixed diff = dot(worldNormal, worldLightDir);
				diff = (diff * 0.5 + 0.5);
				
				float2 k = tex2D(_StrokeTex, i.uv).xy;
				float2 cuv = float2(diff, diff) + k * burn.xy * _InteriorNoiseLevel;
				
				cuv = clamp(cuv, 0.01, 0.99);

				float3 finalColor;
				
				#ifdef _USEKUWAHARA_ON
					finalColor = KuwaharaFilter(_Ramp, cuv);
				#else
					finalColor = GaussianBlur(_Ramp, cuv);
				#endif

				// Rim Light: 边缘高光, 与视线方向夹角大处亮
				#ifdef _USERIMLIGHT_ON
					fixed3 worldViewDir = normalize(UnityWorldSpaceViewDir(i.worldPos));
					fixed rim = 1.0 - saturate(dot(worldViewDir, worldNormal));
					rim = pow(saturate(rim), _RimRate) * _RimIntensity;
					finalColor = lerp(finalColor, _RimColor.rgb, saturate(rim));
				#endif

				return float4(finalColor, 1.0);
			}
			ENDCG
		}
	}
	
	FallBack "Diffuse"
}
