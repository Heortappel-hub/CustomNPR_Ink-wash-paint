Shader "Hidden/SobelInk" {
    Properties {
     _MainTex ("Texture", 2D) = "white" {}
 _PaperTex ("Paper", 2D) = "white" {}
        _InkTex ("Ink", 2D) = "black" {}
        _NoiseTex ("Noise", 2D) = "gray" {}
    }

    CGINCLUDE
    #include "UnityCG.cginc"

  sampler2D _MainTex;
        sampler2D _PaperTex;
        sampler2D _NoiseTex;
        sampler2D _StippleTex;
        sampler2D _InkTex;
        float4 _NoiseTex_TexelSize;
        float4 _MainTex_TexelSize;
        float _LuminanceCorrection;
   float _Contrast;
  float _StippleSize;
        float _EdgeStrength;

  struct VertexData {
          float4 vertex : POSITION;
            float2 uv : TEXCOORD0;
 };

        struct v2f {
     float2 uv : TEXCOORD0;
            float4 vertex : SV_POSITION;
            float4 screenPosition : TEXCOORD1;
 };

     v2f vp(VertexData v) {
  v2f f;
       f.vertex = UnityObjectToClipPos(v.vertex);
       f.uv = v.uv;
f.screenPosition = ComputeScreenPos(f.vertex);
            return f;
    }
    ENDCG

    SubShader {
        Cull Off ZWrite Off ZTest Always

// Pass 0: Luminance 亮度提取
  Pass {
 CGPROGRAM
       #pragma vertex vp
   #pragma fragment fp

     fixed4 fp(v2f i) : SV_Target {
        fixed4 col = tex2D(_MainTex, i.uv);
    float luminance = dot(col.rgb, float3(0.299, 0.587, 0.114));
         return fixed4(luminance, luminance, luminance, luminance);
  }
            ENDCG
        }

        // Pass 1: Sobel 边缘检测
     Pass {
            CGPROGRAM
     #pragma vertex vp
   #pragma fragment fp

    fixed4 fp(v2f i) : SV_Target {
              float Gx = 0.0;
       float Gy = 0.0;

    // Sobel 卷积 - 手动展开避免兼容性问题
                float tl = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * float2(-1, 1)).r;
                float t  = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * float2( 0, 1)).r;
         float tr = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * float2( 1, 1)).r;
           float l  = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * float2(-1, 0)).r;
        float r  = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * float2( 1, 0)).r;
  float bl = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * float2(-1,-1)).r;
         float b  = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * float2( 0,-1)).r;
       float br = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * float2( 1,-1)).r;

       // Sobel X: [-1,0,1; -2,0,2; -1,0,1]
 Gx = -tl - 2.0*l - bl + tr + 2.0*r + br;
    // Sobel Y: [1,2,1; 0,0,0; -1,-2,-1]
          Gy = tl + 2.0*t + tr - bl - 2.0*b - br;

     float Mag = sqrt(Gx * Gx + Gy * Gy);
                Mag = saturate(Mag * _EdgeStrength);

        return fixed4(Mag, Mag, Mag, Mag);
     }
        ENDCG
        }

        // Pass 2: Stippling 点画
        Pass {
          CGPROGRAM
       #pragma vertex vp
       #pragma fragment fp

 fixed4 fp(v2f i) : SV_Target {
     float luminance = tex2D(_MainTex, i.uv).r;

      // 蓝噪声采样
       float2 noiseCoord = i.screenPosition.xy / i.screenPosition.w;
        noiseCoord *= _ScreenParams.xy * _NoiseTex_TexelSize.xy;
      noiseCoord *= _StippleSize;
      float noise = tex2Dlod(_NoiseTex, float4(noiseCoord.xy, 0, 0)).r;

      // 如果没有噪声纹理，使用简单的抖动
         if (_NoiseTex_TexelSize.x == 0) {
           noise = frac(sin(dot(i.uv, float2(12.9898, 78.233))) * 43758.5453);
           }

   // 对比度和亮度校正
     luminance = _Contrast * (luminance - 0.5) + 0.5;
 luminance = saturate(luminance);
       luminance = pow(luminance, 1.0 / _LuminanceCorrection);
         luminance = saturate(luminance);

       // 点画效果
                return luminance < noise ? 1.0 : 0.0;
     }
     ENDCG
        }

        // Pass 3: Combination 组合边缘和点画
        Pass {
CGPROGRAM
       #pragma vertex vp
          #pragma fragment fp

       fixed4 fp(v2f i) : SV_Target {
      float edge = tex2D(_MainTex, i.uv).r;
  float stipple = tex2D(_StippleTex, i.uv).r;

     // 组合
                float result = 1.0 - saturate(edge + stipple);
     return fixed4(result, result, result, 1.0);
            }
            ENDCG
        }

    // Pass 4: Color 最终着色
     Pass {
            CGPROGRAM
            #pragma vertex vp
            #pragma fragment fp

            fixed4 fp(v2f i) : SV_Target {
   float col = tex2D(_MainTex, i.uv).r;
   
            // 采样纹理，如果没有则使用默认颜色
      float4 paper = tex2D(_PaperTex, i.uv);
    float4 ink = tex2D(_InkTex, i.uv);
          
    // 检查纹理是否有效（简单判断）
        // 如果纸张纹理是默认白色，保持白色
      // 如果墨水纹理是默认黑色，保持黑色
    float4 paperColor = float4(0.95, 0.93, 0.88, 1.0); // 米白色纸张
      float4 inkColor = float4(0.1, 0.1, 0.1, 1.0);      // 深灰墨水

      // 使用纹理或默认颜色
       float4 finalPaper = lerp(paperColor, paper, step(0.01, paper.r + paper.g + paper.b));
                float4 finalInk = lerp(inkColor, ink, step(0.01, ink.r + ink.g + ink.b));

           // 简单方式：直接用黑白
 return col >= 0.5 ? paperColor : inkColor;
            }
            ENDCG
        }
    }
}
