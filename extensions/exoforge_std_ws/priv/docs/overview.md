---
nav: Overview
summary: The realtime transport on port 4000: it carries actions and event subscriptions over a W.
---
# WebSocket transport

The realtime transport on port 4000: it carries actions and event subscriptions over a WebSocket, using the shared gateway in `transport`.

## Actions

| Action | Scope | Takes | What it does |
|---|---|---|---|
| `broadcast` | `studio` | `topic`, `event`, `payload` | Broadcasts a frame to an active WebSocket topic. |
| `connection_count` | `studio` | - | Retrieves current active WebSocket connection count. |

## Events

It declares no events.

## Settings

It reads no settings.

## Data

It creates no tables of its own.
