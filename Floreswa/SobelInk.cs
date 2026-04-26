using UnityEngine;

[RequireComponent(typeof(Camera))]
public class SobelInk : MonoBehaviour
{
    [Header("Shader & Textures")]
    public Shader sobelInkShader;
    public Texture paperTexture;
    public Texture inkTexture;
    public Texture blueNoise;

    [Header("Edge Detection")]
    [Range(0.1f, 5.0f)]
    public float edgeStrength = 1.0f;

    [Header("Stippling")]
    [Range(0.01f, 5.0f)]
    public float luminanceContrast = 1.0f;

    [Range(1.0f, 10.0f)]
    public float luminanceCorrection = 1.0f;

    [Range(0.01f, 1.0f)]
    public float stippleSize = 0.5f;

    private Material inkMaterial;

    void OnEnable()
    {
        if (inkMaterial == null && sobelInkShader != null)
        {
            inkMaterial = new Material(sobelInkShader);
            inkMaterial.hideFlags = HideFlags.HideAndDontSave;
        }
    }

    void OnDisable()
    {
        if (inkMaterial != null)
        {
            DestroyImmediate(inkMaterial);
            inkMaterial = null;
        }
    }

    void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (inkMaterial == null)
        {
            Graphics.Blit(source, destination);
            return;
        }


        inkMaterial.SetFloat("_EdgeStrength", edgeStrength);
        inkMaterial.SetFloat("_LuminanceCorrection", luminanceCorrection);
        inkMaterial.SetFloat("_Contrast", luminanceContrast);
        inkMaterial.SetFloat("_StippleSize", stippleSize);
        inkMaterial.SetTexture("_NoiseTex", blueNoise);
        inkMaterial.SetTexture("_InkTex", inkTexture);
        inkMaterial.SetTexture("_PaperTex", paperTexture);

        int width = source.width;
        int height = source.height;


        RenderTexture luminanceRT = RenderTexture.GetTemporary(width, height, 0, source.format);
        Graphics.Blit(source, luminanceRT, inkMaterial, 0);


        RenderTexture edgeRT = RenderTexture.GetTemporary(width, height, 0, source.format);
        Graphics.Blit(luminanceRT, edgeRT, inkMaterial, 1);


        RenderTexture stippleRT = RenderTexture.GetTemporary(width, height, 0, source.format);
        Graphics.Blit(luminanceRT, stippleRT, inkMaterial, 2);


        RenderTexture.ReleaseTemporary(luminanceRT);

        inkMaterial.SetTexture("_StippleTex", stippleRT);
        RenderTexture comboRT = RenderTexture.GetTemporary(width, height, 0, source.format);
        Graphics.Blit(edgeRT, comboRT, inkMaterial, 3);


        RenderTexture.ReleaseTemporary(edgeRT);
        RenderTexture.ReleaseTemporary(stippleRT);

        // Pass 4: 
        Graphics.Blit(comboRT, destination, inkMaterial, 4);

        RenderTexture.ReleaseTemporary(comboRT);
    }
}
