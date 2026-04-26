Shader "ChinesePainting/MountainShader" 
{
	// ==========================================
	// 属性面板 - 在Unity材质Inspector中显示的参数
	// ==========================================
	Properties 
	{
		[Header(OutLine)]  // 分组标题：描边设置
		
		// 描边颜色，默认黑色（水墨画的墨色）
		_StrokeColor ("Stroke Color", Color) = (0,0,0,1)
		
		// 描边噪声贴图，用来让描边看起来不规则、像毛笔画的
		_OutlineNoise ("Outline Noise Map", 2D) = "white" {}
		
		// 描边粗细，0表示无描边，1表示最粗
		_Outline ("Outline", Range(0, 1)) = 0.1
		
		// 飞白效果的宽度倍数，让描边边缘更随机
		_OutsideNoiseWidth ("Outside Noise Width", Range(1, 2)) = 1.3
		
		// 描边的Z轴偏移，防止描边和模型重叠导致闪烁
		_MaxOutlineZOffset ("Max Outline Z Offset", Range(0,1)) = 0.5

		// 新增：距离缩放参数
		_OutlineDistanceScale ("Outline Distance Scale", Range(0.1, 5)) = 1.0
		_OutlineMinWidth ("Outline Min Width", Range(0, 0.5)) = 0.01
		_OutlineMaxWidth ("Outline Max Width", Range(0.5, 2)) = 1.0

		[Header(Interior)]  // 分组标题：内部填充设置
		
		// 色阶渐变贴图，定义水墨的明暗变化（从亮到暗的颜色）
		_Ramp ("Ramp Texture", 2D) = "white" {}
		
		// 笔触纹理贴图，模拟毛笔的纹理效果
		_StrokeTex ("Stroke Noise Tex", 2D) = "white" {}
		
		// 内部噪声贴图，让填充颜色有随机变化
		_InteriorNoise ("Interior Noise Map", 2D) = "white" {}
		
		// 内部噪声强度，值越大，颜色变化越明显
		_InteriorNoiseLevel ("Interior Noise Level", Range(0, 1)) = 0.15
		
		[Header(Filter Settings)]
		// 滤波器切换: 0 = 高斯模糊, 1 = Kuwahara
		[Toggle] _UseKuwahara ("Use Kuwahara Filter", Float) = 0
		
		// Kuwahara 滤波器参数
		_KuwaharaSize ("Kuwahara Size", Range(0.001, 0.1)) = 0.02
		
		// 高斯模糊参数
		_BlurRadius ("Gaussian Blur Radius", Range(0, 60)) = 30
		_Resolution ("Resolution", Float) = 800
		_HStep ("Horizontal Step", Range(0, 1)) = 0.5
		_VStep ("Vertical Step", Range(0, 1)) = 0.5
	}
	
	SubShader 
	{
		// 渲染设置：不透明物体，正常渲染队列
		Tags { "RenderType"="Opaque" "Queue"="Geometry"}

		// ==========================================
		// 第一个Pass：基础描边
		// 原理：把模型背面沿法线方向膨胀，形成轮廓
		// ==========================================
		Pass 
		{
			NAME "OUTLINE"  // Pass的名字，方便调试
			Cull Front      // 剔除正面，只渲染背面（这是描边的关键！）
			
			CGPROGRAM
			#pragma vertex vert    // 指定顶点着色器函数名
			#pragma fragment frag  // 指定片元着色器函数名
			#include "UnityCG.cginc"  // 包含Unity内置的着色器函数库
			
			// 声明变量（必须和Properties中的名字一致）
			float _Outline;           // 描边粗细
			float4 _StrokeColor; // 描边颜色
			sampler2D _OutlineNoise;  // 噪声贴图
			half _MaxOutlineZOffset;  // Z轴偏移量
			float _OutlineDistanceScale;
			float _OutlineMinWidth;
			float _OutlineMaxWidth;

			// 顶点输入结构体 - 从模型获取的数据
			struct a2v 
			{
				float4 vertex : POSITION;  // 顶点位置
				float3 normal : NORMAL;    // 顶点法线（垂直于表面的方向）
			}; 
			
			// 顶点输出结构体 - 传递给片元着色器的数据
			struct v2f 
			{
			    float4 pos : SV_POSITION;  // 屏幕空间位置
			};
			
			// 顶点着色器 - 处理每个顶点
			v2f vert (a2v v) 
			{
				// 用顶点位置采样噪声贴图，获取随机值
				// 这让每个顶点的膨胀量不同，描边看起来不规则
				float4 burn = tex2Dlod(_OutlineNoise, v.vertex);

				// 初始化输出结构体
				v2f o = (v2f)0;
				
				// 把法线从模型空间转换到相机空间
				float3 scaledir = mul((float3x3)UNITY_MATRIX_MV, v.normal);
				
				// 给法线加一个偏移，让描边更均匀
				scaledir += 0.5;
				
				// 把Z分量设得很小，让描边主要在XY平面展开
				scaledir.z = 0.01;
				
				// 归一化，确保方向向量长度为1
				scaledir = normalize(scaledir);

				// 把顶点从模型空间转换到相机空间
				float4 position_cs = mul(UNITY_MATRIX_MV, v.vertex);
				
				// 透视除法，得到标准化的位置
				position_cs /= position_cs.w;

				// 计算从相机到顶点的方向（视线方向）
				float3 viewDir = normalize(position_cs.xyz);
				
				// 沿视线方向偏移顶点，防止描边和模型重叠
				float3 offset_pos_cs = position_cs.xyz + viewDir * _MaxOutlineZOffset;
    
				// 计算相机距离（在相机空间中，-z 就是距离）
				float cameraDistance = -position_cs.z;
				
				// 根据距离计算描边宽度缩放
				// 距离越远，缩放越小；距离越近，缩放越大
				float distanceScale = _OutlineDistanceScale / cameraDistance;
				
				// 限制缩放范围，防止过近或过远时描边异常
				distanceScale = clamp(distanceScale, _OutlineMinWidth, _OutlineMaxWidth);
				
				// 基础线宽计算（保持透视校正）
				float linewidth = cameraDistance / unity_CameraProjection[1].y;
				linewidth = sqrt(linewidth);
				
				// 应用距离缩放
				linewidth *= distanceScale;
				
				// 最终顶点位置 = 偏移位置 + 法线方向 * 线宽 * 噪声值 * 描边参数
				position_cs.xy = offset_pos_cs.xy + scaledir.xy * linewidth * burn.x * _Outline;
				position_cs.z = offset_pos_cs.z;

				// 把相机空间位置转换到裁剪空间（屏幕空间）
				o.pos = mul(UNITY_MATRIX_P, position_cs);

				return o;
			}
			
			// 片元着色器 - 处理每个像素
			fixed4 frag(v2f i) : SV_Target 
			{
				// 直接返回描边颜色，整个描边都是纯色
				fixed4 c = _StrokeColor;
				return c;
			}
			ENDCG
		}
		
		// ==========================================
		// 第二个Pass：飞白描边（随机断续的描边）
		// 比第一个Pass稍宽，但会随机丢弃一些像素
		// 模拟毛笔画的"飞白"效果
		// ==========================================
		Pass 
		{
			NAME "OUTLINE 2"
			Cull Front  // 同样剔除正面
			
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"
			
			float _Outline;
			float4 _StrokeColor;
			sampler2D _OutlineNoise;
			float _OutsideNoiseWidth;  // 飞白宽度倍数
			half _MaxOutlineZOffset;
			float _OutlineDistanceScale;
			float _OutlineMinWidth;
			float _OutlineMaxWidth;

			struct a2v 
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float2 texcoord : TEXCOORD0;  // UV坐标，用于采样贴图
			}; 
			
			struct v2f 
			{
			    float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;  // 传递UV到片元着色器
			};
			
			v2f vert (a2v v) 
			{
				// 采样噪声贴图获取随机值
				float4 burn = tex2Dlod(_OutlineNoise, v.vertex);

				v2f o = (v2f)0;
				
				// 法线转换到相机空间
				float3 scaledir = mul((float3x3)UNITY_MATRIX_MV, v.normal);
				scaledir += 0.5;
				scaledir.z = 0.01;
				scaledir = normalize(scaledir);

				// 顶点转换到相机空间
				float4 position_cs = mul(UNITY_MATRIX_MV, v.vertex);
				position_cs /= position_cs.w;

				// 计算视线方向和偏移
				float3 viewDir = normalize(position_cs.xyz);
				float3 offset_pos_cs = position_cs.xyz + viewDir * _MaxOutlineZOffset;

				// 计算相机距离
				float cameraDistance = -position_cs.z;
				
				// 根据距离计算描边宽度缩放
				float distanceScale = _OutlineDistanceScale / cameraDistance;
				distanceScale = clamp(distanceScale, _OutlineMinWidth, _OutlineMaxWidth);
				
				// 基础线宽计算
				float linewidth = cameraDistance / unity_CameraProjection[1].y;
				linewidth = sqrt(linewidth);
				
				// 应用距离缩放
				linewidth *= distanceScale;
				
				// 飞白描边比基础描边宽 1.1 * _OutsideNoiseWidth 倍
				// 用burn.y而不是burn.x，获取不同的噪声值
				position_cs.xy = offset_pos_cs.xy + scaledir.xy * linewidth * burn.y * _Outline * 1.1 * _OutsideNoiseWidth;
				position_cs.z = offset_pos_cs.z;

				o.pos = mul(UNITY_MATRIX_P, position_cs);
				
				// 传递UV坐标，用于片元着色器中采样
				o.uv = v.texcoord.xy;

				return o;
			}
			
			fixed4 frag(v2f i) : SV_Target 
			{
				fixed4 c = _StrokeColor;
				
				// 用UV坐标采样噪声贴图
				fixed3 burn = tex2D(_OutlineNoise, i.uv).rgb;
				
				// 如果噪声值大于0.5，就丢弃这个像素
				// 这样描边就会出现断断续续的效果，像毛笔的飞白
				if (burn.x > 0.5)
					discard;  // 丢弃像素，不渲染
					
				return c;
			}
			ENDCG
		}
		
		// ==========================================
		// 第三个Pass：内部填充
		// 支持高斯模糊和 Kuwahara 滤波器切换
		// ==========================================
		Pass 
		{
			NAME "INTERIOR"
			Tags { "LightMode"="ForwardBase" }  // 使用前向渲染的基础光照
		
			Cull Back  // 剔除背面，正常渲染正面
			
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fwdbase  // 启用前向渲染的多重编译
			#pragma shader_feature _USEKUWAHARA_ON
			
			#include "UnityCG.cginc"
			#include "Lighting.cginc"    // 光照相关函数
			#include "AutoLight.cginc"   // 自动光照和阴影
			#include "UnityShaderVariables.cginc"
			
			// 声明变量
			sampler2D _Ramp;     // 色阶渐变贴图
			float4 _Ramp_ST;           // 贴图的缩放和偏移
			sampler2D _StrokeTex;    // 笔触纹理
			float4 _StrokeTex_ST;
			float _KuwaharaSize;  // 改为 float 类型，直接控制采样范围
			float _BlurRadius;
			float _Resolution;
			float _HStep;
			float _VStep;
			float _InteriorNoiseLevel; // 噪声强度
			sampler2D _InteriorNoise;  // 内部噪声贴图
			
			struct a2v 
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				float4 texcoord : TEXCOORD0;
				float4 tangent : TANGENT;  // 切线（这里没用到但保留了）
			}; 
		
			struct v2f 
			{
				float4 pos : POSITION;
				float2 uv : TEXCOORD0;         // Ramp贴图的UV
				float3 worldNormal : TEXCOORD1; // 世界空间法线
				float3 worldPos : TEXCOORD2;    // 世界空间位置
				float2 uv2 : TEXCOORD3;      // 笔触贴图的UV
				SHADOW_COORDS(4)        // 阴影坐标（Unity宏）
			};
    

			v2f vert (a2v v) 
			{
				v2f o;
				
				// 顶点转换到裁剪空间
				o.pos = UnityObjectToClipPos(v.vertex);
				
				// 计算两套UV坐标，分别给不同的贴图用
				o.uv = TRANSFORM_TEX(v.texcoord, _Ramp);
				o.uv2 = TRANSFORM_TEX(v.texcoord, _StrokeTex);
				
				// 法线转换到世界空间
				o.worldNormal = UnityObjectToWorldNormal(v.normal);
				
				// 顶点位置转换到世界空间
				o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
				
				// 计算阴影坐标（Unity宏）
				TRANSFER_SHADOW(o);
				
				return o;
			}
			
			// ==========================================
			// Kuwahara 滤波器辅助函数
			// ==========================================
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
			
			// ==========================================
			// 高斯模糊函数
			// ==========================================
			float3 GaussianBlur(sampler2D tex, float2 uv)
			{
				float4 sum = float4(0, 0, 0, 0);
				float blur = _BlurRadius / _Resolution / 4;
				
				// 9-tap 高斯模糊
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
			
			// ==========================================
			// Kuwahara 滤波器函数
			// ==========================================
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
				
				// UV 边缘限制
				if (cuv.x > 0.95) { cuv.x = 0.95; cuv.y = 1; }
				if (cuv.y > 0.95) { cuv.x = 0.95; cuv.y = 1; }
				cuv = clamp(cuv, 0.01, 0.99);

				// 根据开关选择滤波器
				float3 finalColor;
				
				#ifdef _USEKUWAHARA_ON
					// Kuwahara 滤波器 - 保边，笔触感
					finalColor = KuwaharaFilter(_Ramp, cuv);
				#else
					// 高斯模糊 - 柔和晕染
					finalColor = GaussianBlur(_Ramp, cuv);
				#endif

				return float4(finalColor, 1.0);
			}
			ENDCG
		}
	}
	
	// 如果上面的SubShader不支持，就用Unity内置的Diffuse着色器
	FallBack "Diffuse"
}
