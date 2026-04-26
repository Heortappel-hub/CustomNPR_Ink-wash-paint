Shader "Hidden/Ink" {
    Properties {
        _MainTex ("Texture", 2D) = "white" {}
    }

    CGINCLUDE
    #include "UnityCG.cginc"

    sampler2D _MainTex, _CameraDepthTexture;
    sampler2D _PaperTex;
    sampler2D _NoiseTex;
    sampler2D _StippleTex;
    sampler2D _InkTex;
    sampler2D _LumTex;
    float4 _NoiseTex_TexelSize;
    float4 _MainTex_TexelSize;
    float _ContrastThreshold;
    float _LuminanceCorrection;
    float _Contrast;
    float _StippleSize;
    float _BleedRadius;
    float _BleedStrength;
    float _BleedIrregularity;
    float _BleedDensity;
    float _DogSigma;
    float _DogK;
    float _DogGain;
    uint  _UsingImage;

    float4x4 _InvViewProj;
    float _StippleWorldScale;
    float _BleedWorldScale;

    float _BleedViewPower;
    float _BleedPartialThreshold;
    float _BleedDarkThreshold;
    float _BleedDarkSoftness;
    float _BleedDarkOnly;
    float _BleedFadeGamma;
    float _BleedDebug;

    struct VertexData {
        float4 vertex : POSITION;
        float2 uv     : TEXCOORD0;
    };

    struct v2f {
        float2 uv    : TEXCOORD0;
        float4 vertex         : SV_POSITION;
        float4 screenPosition : TEXCOORD1;
    };

    v2f vp(VertexData v) {
        v2f f;
        f.vertex = UnityObjectToClipPos(v.vertex);
        f.uv = v.uv;
        f.screenPosition = ComputeScreenPos(f.vertex);
        return f;
    }

    float3 ReconstructWorldPos(float2 uv) {
        float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
        float4 ndc = float4(uv * 2.0 - 1.0, rawDepth, 1.0);
        #if UNITY_UV_STARTS_AT_TOP
            ndc.y = -ndc.y;
        #endif
        float4 worldPos = mul(_InvViewProj, ndc);
        return worldPos.xyz / worldPos.w;
    }

    float3 ReconstructWorldNormal(float2 uv) {
        float3 c = ReconstructWorldPos(uv);
        float3 r = ReconstructWorldPos(uv + float2(_MainTex_TexelSize.x, 0));
        float3 u = ReconstructWorldPos(uv + float2(0, _MainTex_TexelSize.y));
        float3 n = cross(r - c, u - c);
        return normalize(n);
    }
    ENDCG

    SubShader {
        Cull Off ZWrite Off ZTest Always

        // 0 - Luminance
        Pass {
            CGPROGRAM
            #pragma vertex vp
            #pragma fragment fp

            fixed4 fp(v2f i) : SV_Target {
                float lum = LinearRgbToLuminance(tex2D(_MainTex, i.uv).rgb);
                return fixed4(lum, lum, lum, lum);
            }
            ENDCG
        }

        // 1 - Edge Detection By Contrast
        Pass {
            CGPROGRAM
            #pragma vertex vp
            #pragma fragment fp

            fixed4 fp(v2f i) : SV_Target {
                float m = tex2D(_MainTex, i.uv).r;
                float n = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * float2( 0,  1)).r;
                float e = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * float2( 1,  0)).r;
                float s = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * float2( 0, -1)).r;
                float w = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * float2(-1,  0)).r;

                float contrast = max(max(max(max(n, e), s), w), m) -
                                min(min(min(min(n, e), s), w), m);

                float edge = contrast > _ContrastThreshold ? 1.0 : 0.0;
                return fixed4(edge, edge, edge, edge);
            }
            ENDCG
        }

        // 2 - Edge Detection By Sobel-Feldman Operator
        Pass {
            CGPROGRAM
            #pragma vertex vp
            #pragma fragment fp

            fixed4 fp(v2f i) : SV_Target {
                int3x3 Kx = { 1, 0,-1,  2, 0,-2,  1, 0,-1 };
                int3x3 Ky = { 1, 2, 1,  0, 0, 0, -1,-2,-1 };

                float Gx = 0.0f;
                float Gy = 0.0f;

                [unroll]
                for (int x = -1; x <= 1; ++x) {
                    [unroll]
                    for (int y = -1; y <= 1; ++y) {
                        float2 uv = i.uv + _MainTex_TexelSize.xy * float2(x, y);
                        float l = tex2D(_MainTex, uv).r;
                        Gx += Kx[x + 1][y + 1] * l;
                        Gy += Ky[x + 1][y + 1] * l;
                    }
                }

                float Mag = sqrt(Gx * Gx + Gy * Gy);
                float edge = Mag > _ContrastThreshold ? 1.0 : 0.0;
                return fixed4(edge, edge, edge, edge);
            }
            ENDCG
        }

        // 3 - Edge Detection By Prewitt Operator
        Pass {
            CGPROGRAM
            #pragma vertex vp
            #pragma fragment fp

            fixed4 fp(v2f i) : SV_Target {
                int3x3 Kx = { 1, 0,-1,  1, 0,-1,  1, 0,-1 };
                int3x3 Ky = { 1, 1, 1,  0, 0, 0, -1,-1,-1 };

                float Gx = 0.0f;
                float Gy = 0.0f;

                [unroll]
                for (int x = -1; x <= 1; ++x) {
                    [unroll]
                    for (int y = -1; y <= 1; ++y) {
                        float2 uv = i.uv + _MainTex_TexelSize.xy * float2(x, y);
                        float l = tex2D(_MainTex, uv).r;
                        Gx += Kx[x + 1][y + 1] * l;
                        Gy += Ky[x + 1][y + 1] * l;
                    }
                }

                float Mag = sqrt(Gx * Gx + Gy * Gy);
                float edge = Mag > _ContrastThreshold ? 1.0 : 0.0;
                return fixed4(edge, edge, edge, edge);
            }
            ENDCG
        }

        // 4 - Stippling
        Pass {
            CGPROGRAM
            #pragma vertex vp
            #pragma fragment fp

            float4 fp(v2f i) : SV_Target {
                float luminance = tex2D(_MainTex, i.uv).r;

                float3 wp = ReconstructWorldPos(i.uv);
                float2 noiseCoord = (wp.xz + wp.yy) * _StippleWorldScale;
                noiseCoord *= _StippleSize;
                float noise = tex2Dlod(_NoiseTex, float4(noiseCoord, 0, 0)).a;

                luminance = saturate(_Contrast * (luminance - 0.5) + 0.5);
                luminance = saturate(pow(luminance, 1.0 / _LuminanceCorrection));

                return luminance < noise ? 1.0 : 0.0;
            }
            ENDCG
        }

        // 5 - Combination (edge + stipple)
        Pass {
            CGPROGRAM
            #pragma vertex vp
            #pragma fragment fp

            float4 fp(v2f i) : SV_Target {
                float  edge    = tex2D(_MainTex, i.uv).r;
                float4 stipple = tex2D(_StippleTex, i.uv);
                float  depth   = saturate(1.0 - Linear01Depth(tex2D(_CameraDepthTexture, i.uv).r));

                if (!_UsingImage && depth < 0.0001)
                    stipple *= depth;

                return 1.0 - (edge + stipple);
            }
            ENDCG
        }

        // 6 - Color (paper/ink swap)
        Pass {
            CGPROGRAM
            #pragma vertex vp
            #pragma fragment fp

            float4 fp(v2f i) : SV_Target {
                float4 ink   = tex2D(_InkTex, i.uv);
                float4 paper = tex2D(_PaperTex, i.uv);
                float  col   = tex2D(_MainTex, i.uv).r;
                return col >= 1.0 ? paper : ink;
            }
            ENDCG
        }

        // 7 - Ink Bleed (ÀÆƒ´‘Œ»æ£∫±ﬂ‘µ≤ªπÊ‘Ú¿©…¢)
        Pass {
            CGPROGRAM
            #pragma vertex vp
            #pragma fragment fp

            static const float2 kPoisson12[12] = {
                float2(-0.326, -0.406), float2(-0.840, -0.074),
                float2(-0.696,  0.457), float2(-0.203,  0.621),
                float2( 0.962, -0.195), float2( 0.473, -0.480),
                float2( 0.519,  0.767), float2( 0.185, -0.893),
                float2( 0.507,  0.064), float2( 0.896,  0.412),
                float2(-0.322, -0.933), float2(-0.792, -0.598)
            };

            float4 fp(v2f i) : SV_Target {
                float center = tex2D(_MainTex, i.uv).r;

                float3 wp = ReconstructWorldPos(i.uv);
                float2 wuv = (wp.xz + wp.yy) * _BleedWorldScale;

                float macroNoise = tex2D(_NoiseTex, wuv * 0.6).r;
                float microNoise = tex2D(_NoiseTex, wuv * 7.3 + float2(0.37, 0.11)).r;

                float lum = tex2D(_LumTex, i.uv).r;
                float thr = saturate(_BleedDarkThreshold);
                float sft = max(0.01, _BleedDarkSoftness);
                float darkMask = 1.0 - smoothstep(thr - sft, thr + sft, lum);
                darkMask = lerp(1.0, darkMask, step(0.5, _BleedDarkOnly));

                float n0 = tex2D(_NoiseTex, wuv * 1.7 + float2(0.19, 0.83)).r;
                float n1 = tex2D(_NoiseTex, wuv * 4.3 + float2(0.71, 0.29)).r;
                float n2 = tex2D(_NoiseTex, wuv * 9.1 + float2(0.43, 0.57)).r;
                float partialNoise = n0 * 0.5 + n1 * 0.35 + n2 * 0.15;
                float partialMask = smoothstep(_BleedPartialThreshold,
                                               saturate(_BleedPartialThreshold + 0.25),
                                               partialNoise);

                float bleedMask = saturate(darkMask * partialMask);

                if (bleedMask < 0.01)
                    return float4(center, center, center, center);

                float strength     = max(0.0, _BleedStrength) * bleedMask;
                float strengthNorm = saturate(strength / 3.0);

                float radius = _BleedRadius *
                               lerp(1.0 - _BleedIrregularity, 1.0 + _BleedIrregularity, microNoise) *
                               lerp(0.2, 0.9, strengthNorm);

                float falloffPower = lerp(4.0, 1.6, strengthNorm);

                float accum = center;

                [unroll]
                for (int k = 0; k < 12; ++k) {
                    float2 off    = kPoisson12[k];
                    float  jitter = tex2D(_NoiseTex, wuv * 13.1 + off * 0.27).r;
                    float  r      = radius * (0.35 + jitter);

                    float  e = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * off * r).r;
                    float  falloff = pow(saturate(1.0 - length(off)), falloffPower);

                    accum = max(accum, e * falloff);
                }

                float bleed = pow(saturate(accum * lerp(0.75, 1.15, macroNoise)),
                                  1.0 / max(0.01, _BleedDensity));

                bleed *= strengthNorm;
                bleed  = saturate(bleed + max(0.0, strength - 1.0) * bleed * 0.2);

                float opacity = pow(saturate(bleed), max(0.05, _BleedFadeGamma));
                opacity = saturate(opacity * lerp(0.9, 1.1, microNoise));

                float inkColor = 1.0;
                float target   = lerp(center, inkColor, opacity);

                float result = lerp(center, target, bleedMask);

                float edgeFuzz = tex2D(_NoiseTex, wuv * 25.0).r;
                if (result > 0.05 && result < 0.95)
                    result = saturate(result * lerp(0.85, 1.1, edgeFuzz));

                if (_BleedDebug > 0.5)
                    return float4(bleed, bleed, bleed, 1.0);

                return float4(result, result, result, result);
            }
            ENDCG
        }

        // 8 - DoG (Difference of Gaussians) Edge Detection
        Pass {
            CGPROGRAM
            #pragma vertex vp
            #pragma fragment fp

            float Gauss(float2 d, float sigma) {
                float s2 = sigma * sigma;
                return exp(-dot(d, d) / (2.0 * s2));
            }

            fixed4 fp(v2f i) : SV_Target {
                float sigma1 = max(0.3, _DogSigma);
                float sigma2 = sigma1 * max(1.01, _DogK);

                float sum1 = 0.0, sum2 = 0.0;
                float w1   = 0.0, w2   = 0.0;

                [unroll]
                for (int y = -3; y <= 3; ++y) {
                    [unroll]
                    for (int x = -3; x <= 3; ++x) {
                        float2 o  = float2(x, y);
                        float  l  = tex2D(_MainTex, i.uv + _MainTex_TexelSize.xy * o).r;
                        float  g1 = Gauss(o, sigma1);
                        float  g2 = Gauss(o, sigma2);
                        sum1 += l * g1; w1 += g1;
                        sum2 += l * g2; w2 += g2;
                    }
                }

                float b1 = sum1 / w1;
                float b2 = sum2 / w2;

                float response = abs(b1 - b2) * max(1.0, _DogGain);

                float thr  = _ContrastThreshold;
                float aa   = max(thr * 0.25, 1e-4);
                float edge = smoothstep(thr - aa, thr + aa, response);
                return fixed4(edge, edge, edge, edge);
            }
            ENDCG
        }
    }
}