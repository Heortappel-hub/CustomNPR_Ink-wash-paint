using UnityEngine;
using UnityEngine.InputSystem;

public class CameraController : MonoBehaviour
{
    [Header("Move Settings")]
    public float moveSpeed = 5f;
    public float fastMoveMultiplier = 2f;
    public float verticalMoveSpeed = 3f;

    [Header("Look Settings")]
    public float lookSpeed = 0.1f;
    public bool holdRightMouseToLook = true;

    private float yaw;
    private float pitch;

    void Start()
    {
        Vector3 angles = transform.eulerAngles;
        yaw = angles.y;
        pitch = angles.x;
    }

    void Update()
    {
        HandleMovement();
        HandleRotation();
    }

    void HandleMovement()
    {
        Vector2 moveInput = Vector2.zero;

        if (Keyboard.current.wKey.isPressed) moveInput.y += 1;
        if (Keyboard.current.sKey.isPressed) moveInput.y -= 1;
        if (Keyboard.current.aKey.isPressed) moveInput.x -= 1;
        if (Keyboard.current.dKey.isPressed) moveInput.x += 1;

        float upDown = 0f;
        if (Keyboard.current.qKey.isPressed) upDown -= 1f;
        if (Keyboard.current.eKey.isPressed) upDown += 1f;

        float currentSpeed = moveSpeed;
        if (Keyboard.current.leftShiftKey.isPressed)
        {
            currentSpeed *= fastMoveMultiplier;
        }

        Vector3 move =
            transform.forward * moveInput.y +
            transform.right * moveInput.x +
            transform.up * upDown * (verticalMoveSpeed / moveSpeed);

        transform.position += move * currentSpeed * Time.deltaTime;
    }

    void HandleRotation()
    {
        if (holdRightMouseToLook && !Mouse.current.rightButton.isPressed)
            return;

        Vector2 mouseDelta = Mouse.current.delta.ReadValue();

        yaw += mouseDelta.x * lookSpeed;
        pitch -= mouseDelta.y * lookSpeed;
        pitch = Mathf.Clamp(pitch, -89f, 89f);

        transform.rotation = Quaternion.Euler(pitch, yaw, 0f);
    }
}