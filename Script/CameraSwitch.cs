using UnityEngine;

public class CameraSwitcher : MonoBehaviour
{
    public GameObject camera1;
    public GameObject camera2;

    void Update()
    {
        if (Input.GetKeyDown(KeyCode.Space)) // °´¿Õ¸ñ¼üÇÐ»»
        {
            // ÇÐ»»×´Ì¬
            camera1.SetActive(!camera1.activeSelf);
            camera2.SetActive(!camera2.activeSelf);
        }
    }
}