using System.Collections;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

[RequireComponent(typeof(Camera))]
public class Ink : MonoBehaviour
{

    public Shader inkShader;
    public Texture paperTexture;
    public Texture inkTexture;

    public Texture image;
    public bool useImage = false;

    public Texture blueNoise;

    public enum EdgeDetector
    {
        contrast = 1,
        sobelFeldman = 2,
        prewitt = 3,
        dog = 4  // DoG 边缘检测（已与其他边缘检测合并到 1~4）
    }
    public EdgeDetector edgeDetector = EdgeDetector.sobelFeldman;

    [Range(0.01f, 1.0f)]
    public float contrastThreshold = 0.5f;

    [Header("DoG")]
    [Range(0.3f, 3.0f)] public float dogSigma = 1.0f;
    [Range(1.1f, 3.0f)] public float dogK = 1.6f;
    [Range(1.0f, 100.0f)] public float dogGain = 20.0f;

    [Range(0.01f, 5.0f)]
    public float luminanceContrast = 1.0f;

    [Range(1.0f, 10.0f)]
    public float luminanceCorrection = 1.0f;

    [Range(0.01f, 1.0f)]
    public float stippleSize = 1.0f;

    [Header("Ink Bleed (水墨晦染)")]
    [Range(0.0f, 3.0f)] public float bleedAmount = 1.2f;
    [Range(0.0f, 30.0f)] public float bleedRadius = 10.0f;
    [Range(0.0f, 1.0f)] public float bleedIrregularity = 0.8f;
    [Range(1, 3)] public int bleedIterations = 2;
    [Range(0.5f, 3.0f)] public float bleedDensity = 1.5f;

    [Header("时间一致性 (噪点锚定到世界空间)")]
    [Range(0.1f, 20.0f)] public float stippleWorldScale = 4.0f; // 点刻在世界空间的平铺密度
    [Range(0.1f, 20.0f)] public float bleedWorldScale = 1.5f; // 墨晦噪声的世界空间平铺密度

    [Header("Ink Bleed - Dark Edge (只扩散暗部边缘)")]
    [Tooltip("开启后只扩散暗部边缘；关闭则全部边缘都扩散")]
    public bool bleedDarkOnly = true;
    [Tooltip("低于此亮度的像素才参与扩散，1=全部扩散，0=都不扩散")]
    [Range(0.0f, 1.0f)] public float bleedDarkThreshold = 0.45f;
    [Tooltip("暗部 mask 过渡带宽，越大过渡越柔和")]
    [Range(0.01f, 0.5f)] public float bleedDarkSoftness = 0.15f;

    [Tooltip("部分选择阈值，0 ≈ 全部轮廓都晕，1 ≈ 全部不晕；用于制造断续感")]
    [Range(0.0f, 1.0f)] public float bleedPartialThreshold = 0.35f;

    [Header("Ink Bleed - Fade (透明度合成)")]
    [Tooltip("bleed 作为墨的不透明度曲线；1=线性，>1 边缘浓中心快速透明，<1 过渡更柔")]
    [Range(0.2f, 5.0f)] public float bleedFadeGamma = 1.5f;
    [Tooltip("调试：直接输出 bleed 的灰度，用于确认扩散范围")]
    public bool bleedDebug = false;

    public bool capturing = false;

    private Material inkMaterial;
    private int frameCount = 0;

    // Shader Pass 常量
    const int PASS_LUMINANCE = 0;
    const int PASS_STIPPLE = 5;
    const int PASS_COMBINE = 6;
    const int PASS_COLOR = 7;
    const int PASS_INK_BLEED = 8;

    void OnEnable()
    {
        if (inkMaterial == null)
        {
            inkMaterial = new Material(inkShader);
            inkMaterial.hideFlags = HideFlags.HideAndDontSave;
        }
    }

    void OnDisable()
    {
        inkMaterial = null;
    }

    void Start()
    {
        Camera cam = GetComponent<Camera>();
        cam.depthTextureMode = cam.depthTextureMode | DepthTextureMode.Depth;
    }

    void Update()
    {
        ++frameCount;
    }

    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        // ---------- General ----------
        inkMaterial.SetFloat("_EdgeThreshold", contrastThreshold);
        inkMaterial.SetFloat("_LuminanceContrast", luminanceContrast);
        inkMaterial.SetFloat("_LuminanceCorrection", luminanceCorrection);
        inkMaterial.SetFloat("_UseInputImage", useImage ? 1f : 0f);

        // ---------- Textures ----------
        inkMaterial.SetTexture("_TexNoise", blueNoise);

        // ---------- Stipple ----------
        inkMaterial.SetFloat("_StippleSize", stippleSize);
        inkMaterial.SetFloat("_StippleWorldScale", stippleWorldScale);

        // ---------- Bleed ----------
        float safeDensity = Mathf.Max(0.5f, bleedDensity);
        int safeIter = Mathf.Max(1, bleedIterations);

        inkMaterial.SetFloat("_BleedStrength", bleedAmount);
        inkMaterial.SetFloat("_BleedRadius", bleedRadius);
        inkMaterial.SetFloat("_BleedIrregularity", bleedIrregularity);
        inkMaterial.SetFloat("_BleedDensity", safeDensity);
        inkMaterial.SetFloat("_BleedWorldScale", bleedWorldScale);
        inkMaterial.SetFloat("_BleedDarkOnly", bleedDarkOnly ? 1f : 0f);
        inkMaterial.SetFloat("_BleedDarkThreshold", bleedDarkThreshold);
        inkMaterial.SetFloat("_BleedDarkSoftness", bleedDarkSoftness);
        inkMaterial.SetFloat("_BleedPartialThreshold", bleedPartialThreshold);
        inkMaterial.SetFloat("_BleedFadeGamma", bleedFadeGamma);
        inkMaterial.SetFloat("_BleedDebug", bleedDebug ? 1f : 0f);

        // ---------- DoG ----------
        inkMaterial.SetFloat("_DoGSigma", dogSigma);
        inkMaterial.SetFloat("_DoGK", dogK);
        inkMaterial.SetFloat("_DoGGain", dogGain);

        // ---------- Matrices ----------
        Camera cam = GetComponent<Camera>();
        Matrix4x4 gpuProj = GL.GetGPUProjectionMatrix(cam.projectionMatrix, true);
        Matrix4x4 viewProj = gpuProj * cam.worldToCameraMatrix;
        inkMaterial.SetMatrix("_InvViewProj", viewProj.inverse);

        int width = useImage ? image.width : source.width;
        int height = useImage ? image.height : source.height;
        RenderTextureFormat fmt = source.format;

        // --- Luminance ---
        RenderTexture luminanceRT = RenderTexture.GetTemporary(width, height, 0, fmt);
        Graphics.Blit(useImage ? image : source, luminanceRT, inkMaterial, PASS_LUMINANCE);

        // --- Edge Detection ---
        RenderTexture edgeRT = RenderTexture.GetTemporary(width, height, 0, fmt);
        Graphics.Blit(luminanceRT, edgeRT, inkMaterial, (int)edgeDetector);

        // Bleed 需要原始亮度图作为暗部门控
        inkMaterial.SetTexture("_TexLuminance", luminanceRT);

        // --- Ink Bleed (多次迭代) ---
        if (bleedAmount > 0.001f && bleedRadius > 0.001f && blueNoise != null)
        {
            RenderTexture src = edgeRT;
            for (int it = 0; it < safeIter; ++it)
            {
                RenderTexture dst = RenderTexture.GetTemporary(width, height, 0, fmt);
                Graphics.Blit(src, dst, inkMaterial, PASS_INK_BLEED);
                if (src != edgeRT) RenderTexture.ReleaseTemporary(src);
                src = dst;
            }
            RenderTexture.ReleaseTemporary(edgeRT);
            edgeRT = src;
        }

        // --- Stipple ---
        RenderTexture stippleRT = RenderTexture.GetTemporary(width, height, 0, fmt);
        Graphics.Blit(luminanceRT, stippleRT, inkMaterial, PASS_STIPPLE);
        RenderTexture.ReleaseTemporary(luminanceRT);

        inkMaterial.SetTexture("_TexStipple", stippleRT);

        // --- Combine ---
        RenderTexture comboRT = RenderTexture.GetTemporary(width, height, 0, fmt);
        Graphics.Blit(edgeRT, comboRT, inkMaterial, PASS_COMBINE);
        RenderTexture.ReleaseTemporary(edgeRT);
        RenderTexture.ReleaseTemporary(stippleRT);

        // --- Color (final) ---
        inkMaterial.SetTexture("_TexInk", inkTexture);
        inkMaterial.SetTexture("_TexPaper", paperTexture);
        Graphics.Blit(comboRT, destination, inkMaterial, PASS_COLOR);
        RenderTexture.ReleaseTemporary(comboRT);
    }

    private void LateUpdate()
    {
        if (capturing || IsCaptureKeyPressed())
        {
            int width = useImage ? image.width : 600;
            int height = useImage ? image.height : 600;

            RenderTexture rt = new RenderTexture(width, height, 24);
            GetComponent<Camera>().targetTexture = rt;
            Texture2D screenshot = new Texture2D(width, height, TextureFormat.RGB24, false);
            GetComponent<Camera>().Render();
            RenderTexture.active = rt;
            screenshot.ReadPixels(new Rect(0, 0, width, height), 0, 0);
            GetComponent<Camera>().targetTexture = null;
            RenderTexture.active = null;
            Destroy(rt);

            // 确保 Recordings 目录存在，避免 DirectoryNotFoundException
            string dir = string.Format("{0}/../Recordings", Application.dataPath);
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);

            string filename = string.Format("{0}/snap_{1}.png", dir, System.DateTime.Now.ToString("HH-mm-ss"));
            System.IO.File.WriteAllBytes(filename, screenshot.EncodeToPNG());
        }
    }

    // 在 Inspector 修改/场景载入时纠正非法值
    private void OnValidate()
    {
        if (bleedDensity < 0.5f) bleedDensity = 1.5f;
        if (bleedIterations < 1) bleedIterations = 2;

        // 兼容旧场景：把非法或已废弃的 edgeDetector 值映射到 Sobel
        int ev = (int)edgeDetector;
        if (ev != 1 && ev != 2 && ev != 3 && ev != 4)
            edgeDetector = EdgeDetector.sobelFeldman;
    }

    private static bool IsCaptureKeyPressed()
    {
#if ENABLE_INPUT_SYSTEM
        var kb = Keyboard.current;
        return kb != null && kb.spaceKey.wasPressedThisFrame;
#else
        return Input.GetKeyDown(KeyCode.Space);
#endif
    }
}
