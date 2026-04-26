using UnityEngine;
using UnityEngine.InputSystem;

public class LightController : MonoBehaviour
{
    public float moveSpeed = 3f;
    public float fastMultiplier = 2f;

    void Update()
    {
        float x = 0f;
        float z = 0f;
        float y = 0f;

        // 左右（J L）
        if (Keyboard.current.jKey.isPressed) x = -1f;
        if (Keyboard.current.lKey.isPressed) x = 1f;

        // 前后（I K）
        if (Keyboard.current.iKey.isPressed) z = 1f;
        if (Keyboard.current.kKey.isPressed) z = -1f;

        // 上下（U O）
        if (Keyboard.current.uKey.isPressed) y = -1f;
        if (Keyboard.current.oKey.isPressed) y = 1f;

        float speed = moveSpeed;

        if (Keyboard.current.leftShiftKey.isPressed)
        {
            speed *= fastMultiplier;
        }

        Vector3 move = new Vector3(x, y, z);

        transform.Translate(move * speed * Time.deltaTime, Space.World);
    }
}