/*
 * Sample WASM plugin guest.
 *
 * Compiled to a WASI reactor by build.sh. Each export corresponds to an [ExoAction] on
 * SampleWasmPlugin.cs; the host bridge functions map to the `env` imports wired up by
 * Exoforge.Drivers.Runtime.WasmPluginRunner.
 */
#include <stdio.h>
#include <string.h>

__attribute__((import_module("env"), import_name("host_emit_event")))
extern int host_emit_event(const char* topic, int topic_len, const char* event, int event_len, const char* payload, int payload_len);

__attribute__((import_module("env"), import_name("host_log")))
extern int host_log(int level, const char* msg, int msg_len);

__attribute__((export_name("ping")))
int ping(void) {
    return 42;
}

__attribute__((export_name("increment")))
int increment(int counter_id, int amount) {
    int new_value = amount > 0 ? amount : 1;

    const char* topic = "sample:events";
    const char* event = "value_changed";
    char payload[128];
    int len = snprintf(payload, sizeof payload,
        "{\"counter_id\":%d,\"new_value\":%d,\"delta\":%d}", counter_id, new_value, amount);

    host_emit_event(topic, (int)strlen(topic), event, (int)strlen(event), payload, len);
    return new_value;
}

__attribute__((export_name("echo")))
int echo(int value) {
    return value;
}
