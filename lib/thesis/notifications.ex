defmodule Thesis.Notifications do
  @moduledoc """
  Builds a map of Notifications that is passed to the client side. The key should be a
  representation of the category/type of notification (this is used to determine where and how it's
  displayed). The value is a list of notification strings.

  Example of final map:
  %{
    "page-settings": [],
    "add-page": [],
    "import-export-restore": [],
    "other": []
  }
  """

  alias Thesis.Backup
  import Thesis.Config
  import Thesis.Utilities
  import Ecto.Query, only: [limit: 2]

  @allowed_notification_keys [
    "page-settings",
    "add-page",
    "import-export-restore",
    "other",
    :page_settings,
    :add_page,
    :import_export_restore,
    :other
  ]

  def all(conn) do
    %{
      "page-settings" => [],
      "add-page" => [],
      "import-export-restore" => [],
      "other" => []
    }
    |> notifications_from_host_app(conn, notifications())
    |> notifications_regarding_env
    |> notifications_regarding_page(conn.assigns[:thesis_page])
  end

  # TODO: add page specific-notifications
  def notifications_regarding_page(acc, nil), do: acc
  def notifications_regarding_page(acc, %_{}) do
    acc
  end

  def notifications_regarding_env(acc) do
    acc
    |> notification_to_run_migration_for_version_0_3_0()
  end

  @doc """
  Adds notifications provided by the host app to the accumulator.

      iex> notifications_from_host_app(%{"page-settings" => []}, nil, [page_settings: ["notif"]])
      %{"page-settings" => ["notif"]}
      iex> notifications_from_host_app(%{"page-settings" => []}, nil, [page_settings: :invalid])
      %{"page-settings" => []}
      iex> notifications_from_host_app(%{"page-settings" => ["notif1"]}, nil, [page_settings: ["notif2"]])
      %{"page-settings" => ["notif2", "notif1"]}
      iex> notifications_from_host_app(%{"other" => [], "add-page" => ["notif"]}, nil, [other: ["notif"]])
      %{"other" => ["notif"], "add-page" => ["notif"]}
      iex> notifications_from_host_app(%{"other" => []}, nil, nil)
      %{"other" => []}
  """
  def notifications_from_host_app(acc, conn, notifications) when is_list(notifications) do
    case verify_notifications_structure(conn, notifications) do
      true ->
        Enum.reduce(notifications, acc, fn({type, list}, acc) ->
          update_notifications_map(acc, conn, type, list)
        end)
      _ -> acc
    end
  end
  def notifications_from_host_app(acc, _, _), do: acc

  @doc """
  Verifies that the notifications provided by the host app are in the correct format.

      iex> verify_notifications_structure(nil, [:invalid])
      false
      iex> verify_notifications_structure(nil, %{})
      false
      iex> verify_notifications_structure(nil, %{invalid_key: []})
      false
      iex> verify_notifications_structure(nil, %{add_page: "invalid value"})
      false
      iex> verify_notifications_structure(nil, %{add_page: ["notif", "notif", :atom]})
      false
      iex> verify_notifications_structure(nil, [add_page: [], page_settings: ["notif"]])
      false
  """
  def verify_notifications_structure(_conn, notifications) when is_list(notifications) and length(notifications) == 0, do: false
  def verify_notifications_structure(conn, notifications) when is_list(notifications) do
    case Keyword.keyword?(notifications) do
      true ->
        notifications
        |> Enum.map(fn(n) ->
          n
          |> is_notification_key_allowed?()
          |> is_notification_value_data_type_valid?()
          |> is_notification_value_valid?(conn)
        end)
        |> Enum.all?()
      _ -> false
    end
  end
  def verify_notifications_structure(_, _), do: false

  defp update_notifications_map(acc, conn, type, notifications_list) when is_function(notifications_list) do
    update_notifications_map(acc, conn, type, notifications_list.(conn))
  end
  defp update_notifications_map(acc, conn, type, notifications_list) when is_atom(type) do
    update_notifications_map(acc, conn, parameterize(type), notifications_list)
  end
  defp update_notifications_map(acc, _conn, type, notifications_list) do
    %{acc | type => notifications_list ++ acc["#{type}"]}
  end

  # UTILITIES
  defp version() do
    {:ok, version} = :application.get_key(:thesis, :vsn)
    List.to_string(version)
  end

  defp is_notification_key_allowed?({k, _} = n) when k in @allowed_notification_keys, do: n
  defp is_notification_key_allowed?(_), do: false

  defp is_notification_value_data_type_valid?({_, v} = n) when is_list(v) or is_function(v), do: n
  defp is_notification_value_data_type_valid?(_), do: false

  defp is_notification_value_valid?({_, v}, _) when is_list(v) and length(v) == 0, do: false
  defp is_notification_value_valid?({k, v}, conn) when is_function(v) do
    is_notification_value_valid?({k, v.(conn)}, conn)
  end
  defp is_notification_value_valid?({_, v} = n, _) when is_list(v) do
    case is_list(v) and Enum.all?(v, &is_binary/1) do
      true -> n
      _ -> false
    end
  end
  defp is_notification_value_valid?(_, _), do: false

  # NOTIFICATIONS
  # remove in 0.3.1: reminder that revisions will not work without the new migration
  defp notification_to_run_migration_for_version_0_3_0(acc) do
    notification_to_run_migration_for_version_0_3_0(acc, Version.compare("0.3.0", version()))
  end
  defp notification_to_run_migration_for_version_0_3_0(acc, nil), do: acc
  defp notification_to_run_migration_for_version_0_3_0(acc, c) when is_atom(c) and c in [:eq, :gt] do
    notification_to_run_migration_for_version_0_3_0(acc, repo().one(limit(Backup, 1)))
  end
  defp notification_to_run_migration_for_version_0_3_0(acc, %{page_data: data}) do
    notification_to_run_migration_for_version_0_3_0(acc, String.valid?(data))
  end
  defp notification_to_run_migration_for_version_0_3_0(acc, false) do
    update_notifications_map(acc, nil, "import-export-restore", ["Page revisions may not work! Please ask your developer to update Thesis."])
  end
  defp notification_to_run_migration_for_version_0_3_0(acc, _), do: acc
end
