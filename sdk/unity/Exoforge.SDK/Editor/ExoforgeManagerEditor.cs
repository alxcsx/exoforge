using UnityEditor;
using UnityEngine;
using Exoforge.Client;
using Exoforge.Client.Unity;

namespace Exoforge.Unity.Editor;

[CustomEditor(typeof(ExoforgeManager))]
public class ExoforgeManagerEditor : UnityEditor.Editor
{
    public override void OnInspectorGUI()
    {
        var behaviour = (ExoforgeManager)target;

        // Custom Header Status Banner
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.BeginHorizontal();
        EditorGUILayout.LabelField("Exoforge Network Hub", EditorStyles.boldLabel);
        GUILayout.FlexibleSpace();

        bool isConnected = behaviour.IsConnected;
        var prevColor = GUI.color;
        GUI.color = isConnected ? new Color(0.3f, 0.9f, 0.4f) : new Color(0.7f, 0.7f, 0.7f);
        GUILayout.Label(isConnected ? "● ONLINE" : "○ OFFLINE", EditorStyles.miniBoldLabel);
        GUI.color = prevColor;

        EditorGUILayout.EndHorizontal();

        if (isConnected)
        {
            string playerId = !string.IsNullOrEmpty(ExoTokenStore.PlayerId) ? ExoTokenStore.PlayerId : "(unauthenticated)";
            EditorGUILayout.LabelField($"Active Session: {playerId}", EditorStyles.miniLabel);
        }

        EditorGUILayout.EndVertical();

        EditorGUILayout.Space(4);

        // Default serialized fields
        DrawDefaultInspector();

        EditorGUILayout.Space(6);

        // Exoforge Studio Link & Runtime Actions
        EditorGUILayout.BeginVertical(EditorStyles.helpBox);
        EditorGUILayout.LabelField("Quick Actions", EditorStyles.boldLabel);

        if (GUILayout.Button("Open Exoforge Studio", GUILayout.Height(26)))
        {
            ExoforgeControlCenter.ShowWindow();
        }

        if (Application.isPlaying)
        {
            EditorGUILayout.Space(2);
            if (!isConnected)
            {
                if (GUILayout.Button("Connect Now (Runtime)"))
                {
                    _ = behaviour.ConnectAsync();
                }
            }
            else
            {
                if (GUILayout.Button("Disconnect (Runtime)"))
                {
                    if (behaviour.Client != null)
                    {
                        _ = behaviour.Client.DisconnectAsync();
                    }
                }
            }
        }

        EditorGUILayout.EndVertical();
    }
}
