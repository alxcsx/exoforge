#if UNITY_2018_1_OR_NEWER
using UnityEngine;

namespace Exoforge.Client.Unity;

/// <summary>
/// Unity component that manages the lifecycle of the ExoClient and
/// pumps the ExoDispatcher on the main Unity thread update loop.
/// Ensures all network callbacks, action results, and events execute safely on the main thread.
/// </summary>
[DefaultExecutionOrder(-1000)]
public class ExoforgeBehaviour : MonoBehaviour
{
    private static ExoforgeBehaviour? _instance;
    public static ExoforgeBehaviour Instance => _instance!;

    public ExoClient? Client { get; private set; }

    private void Awake()
    {
        if (_instance != null && _instance != this)
        {
            Destroy(gameObject);
            return;
        }

        _instance = this;
        DontDestroyOnLoad(gameObject);
    }

    public void Initialize(ExoClient client)
    {
        Client = client;
    }

    private void Update()
    {
        Client?.Dispatcher.Update();
    }

    private async void OnDestroy()
    {
        if (Client != null)
        {
            await Client.DisconnectAsync();
            Client.Dispose();
        }
    }
}
#endif
