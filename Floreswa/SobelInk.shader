Shader "Hidden/SobelInk" {
    Properties {
     _MainTex ("Texture", 2D) = "white" {}
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
             float luminance = LinearRgbToLuminance(col.rgb);
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
    // Sobel 卷积核
                int3x3 Kx = {
    1, 0, -1,
   2, 0, -2,
    1, 0, -1
     };

    int3x3 Ky = {
 1, 2, 1,
           0, 0, 0,
  -1, -2, -1
                };

                float Gx = 0.0f;
      float Gy = 0.0f;

         // 3x3 卷积
    for (int x = -1; x <= 1; ++x) {
     for (int y = -1; y <= 1; ++y) {
      float2 uv = i.uv + _MainTex_TexelSize.xy * float2(x, y);
             float l = tex2D(_MainTex, uv).r;
       Gx += Kx[x + 1][y + 1] * l;
       Gy += Ky[x + 1][y + 1] * l;
            }
 }

   // 计算梯度幅值
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
      float noise = tex2Dlod(_NoiseTex, float4(noiseCoord.x, noiseCoord.y, 0, 0)).a;

            // 对比度和亮度校正
    luminance = _Contrast * (luminance - 0.5f) + 0.5f;
    luminance = saturate(luminance);
     luminance = pow(luminance, 1.0f / _LuminanceCorrection);
                luminance = saturate(luminance);

          // 点画效果：亮度低于噪声阈值则显示墨点
      return luminance < noise ? 1.0f : 0.0f;
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

       // 组合：1 - (边缘 + 点画)，白色为纸张，黑色为墨水
    float result = 1.0f - saturate(edge + stipple);
         return fixed4(result, result, result, 1.0f);
         }
  ENDCG
}

        // Pass 4: Color 最终着色
     Pass {
 CGPROGRAM
            #pragma vertex vp
            #pragma fragment fp

   fixed4 fp(v2f i) : SV_Target {
         float4 ink = tex2D(_InkTex, i.uv);
    float4 paper = tex2D(_PaperTex, i.uv);
          float col = tex2D(_MainTex, i.uv).r;

         // 根据值选择纸张或墨水纹理
                return col >= 0.5f ? paper : ink;
    }
         ENDCG
        }
  }
}
