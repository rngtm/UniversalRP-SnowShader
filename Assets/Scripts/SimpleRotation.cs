using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class SimpleRotation : MonoBehaviour
{
    [SerializeField] private Vector3 rotate;

    void FixedUpdate()
    {
        transform.Rotate(rotate * Time.fixedDeltaTime);
    }
}
