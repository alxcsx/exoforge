defmodule Exoforge.Std.Http.OpenAPI do
  @moduledoc """
  Generates an OpenAPI 3.0 specification dynamically from registered Exoforge
  contracts, actions, parameter types, return types, and scopes.
  """

  alias Exoforge.PluginRegistry

  @doc "Generates a complete OpenAPI 3.0 specification map."
  def generate do
    paths = build_paths()

    %{
      openapi: "3.0.3",
      info: %{
        title: "Exoforge Game Backend REST API",
        description:
          "Automatically generated OpenAPI 3.0 specification derived from active Exoforge service contracts and plugins.",
        version: "1.0.0"
      },
      servers: [
        %{
          url: "http://localhost:4001",
          description: "Local Exoforge REST API Gateway"
        }
      ],
      paths: paths,
      components: %{
        securitySchemes: %{
          bearerAuth: %{
            type: "http",
            scheme: "bearer",
            bearerFormat: "Token",
            description: "Authentication token passed via Authorization: Bearer <token>"
          }
        }
      }
    }
  end

  defp build_paths do
    # Built-in endpoints
    base_paths = %{
      "/health" => %{
        get: %{
          tags: ["System"],
          summary: "Gateway Health Check",
          description: "Returns health status of the HTTP REST gateway.",
          responses: %{
            "200" => %{
              description: "Gateway is operational",
              content: %{
                "application/json" => %{
                  schema: %{
                    type: "object",
                    properties: %{status: %{type: "string", example: "ok"}}
                  }
                }
              }
            }
          }
        }
      },
      "/api/status" => %{
        get: %{
          tags: ["System"],
          summary: "Service Status",
          responses: %{
            "200" => %{description: "Service status information"}
          }
        }
      },
      "/api/routes" => %{
        get: %{
          tags: ["System"],
          summary: "List Registered Contract Routes",
          responses: %{
            "200" => %{description: "List of all active service routes"}
          }
        }
      }
    }

    # Dynamic paths generated from active contracts
    contract_paths =
      PluginRegistry.all_manifests()
      |> Enum.flat_map(fn manifest ->
        provides = Map.get(manifest, :provides, [])

        Enum.flat_map(provides, fn contract_ref ->
          contract_mod = PluginRegistry.resolve_contract_module(contract_ref)

          if is_atom(contract_mod) and Code.ensure_loaded?(contract_mod) and
               function_exported?(contract_mod, :__service_metadata__, 0) do
            meta = contract_mod.__service_metadata__()
            service_name = to_string(meta.name)
            actions = Map.get(meta, :actions, [])

            Enum.map(actions, fn action ->
              path = "/api/#{service_name}/#{action.name}"
              op = build_action_operation(service_name, action, manifest)
              {path, %{post: op}}
            end)
          else
            []
          end
        end)
      end)
      |> Enum.into(%{})

    Map.merge(base_paths, contract_paths)
  end

  defp build_action_operation(service_name, action, manifest) do
    summary = action[:doc] || "#{service_name}.#{action.name}"
    scope = action[:scope]

    properties =
      (action[:params] || [])
      |> Enum.map(fn {param_name, param_type} ->
        {to_string(param_name), schema_for_type(param_type)}
      end)
      |> Enum.into(%{})

    required_fields =
      (action[:params] || [])
      |> Enum.map(fn {param_name, _} -> to_string(param_name) end)

    request_body =
      if properties == %{} do
        %{
          required: false,
          content: %{
            "application/json" => %{
              schema: %{type: "object"}
            }
          }
        }
      else
        %{
          required: true,
          content: %{
            "application/json" => %{
              schema: %{
                type: "object",
                properties: properties,
                required: required_fields
              }
            }
          }
        }
      end

    security =
      if scope && scope != :global do
        [%{"bearerAuth" => [to_string(scope)]}]
      else
        []
      end

    op = %{
      tags: [Macro.camelize(service_name)],
      summary: to_string(action.name),
      description: "Provided by plugin `#{manifest.id}`. #{summary}",
      requestBody: request_body,
      responses: %{
        "200" => %{description: "Action executed successfully"},
        "400" => %{description: "Invalid payload or execution error"},
        "401" => %{description: "Unauthorized - missing or invalid token"},
        "403" => %{description: "Forbidden - insufficient permissions for scope #{inspect(scope)}"},
        "404" => %{description: "Service or action not found"}
      }
    }

    if security != [] do
      Map.put(op, :security, security)
    else
      op
    end
  end

  defp schema_for_type(:string), do: %{type: "string"}
  defp schema_for_type(:integer), do: %{type: "integer"}
  defp schema_for_type(:float), do: %{type: "number", format: "float"}
  defp schema_for_type(:boolean), do: %{type: "boolean"}
  defp schema_for_type(:map), do: %{type: "object"}
  defp schema_for_type(:list), do: %{type: "array", items: %{type: "string"}}
  defp schema_for_type(_), do: %{type: "string"}
end
