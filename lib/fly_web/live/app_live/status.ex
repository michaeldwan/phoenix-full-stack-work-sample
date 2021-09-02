defmodule FlyWeb.AppLive.Status do
  use FlyWeb, :live_view
  require Logger

  alias Fly.Client
  alias FlyWeb.Components.HeaderBreadcrumbs

  @impl true
  def mount(%{"name" => name}, session, socket) do
    socket =
      assign(socket,
        config: client_config(session),
        state: :loading,
        app: nil,
        app_name: name,
        vms: [],
        count: 0,
        authenticated: true
      )

    # Only make the API call if the websocket is setup. Not on initial render.
    if connected?(socket) do
      Process.send_after(self(), :refresh_status, 0)
      {:ok, socket}
      # {:ok, fetch_data(socket)}
    else
      {:ok, socket}
    end
  end

  defp client_config(session) do
    Fly.Client.config(access_token: session["auth_token"] || System.get_env("FLYIO_ACCESS_TOKEN"))
  end

  @impl true
  def handle_info(:refresh_status, socket) do
    Logger.info("refreshing status")

    app_name = socket.assigns.app_name

    socket =
      case Client.fetch_app_vms(app_name, false, socket.assigns.config) do
        {:ok, app} ->
          socket
          |> assign(:app, app)
          |> assign(:vms, app["vms"]["nodes"])

        {:error, :unauthorized} ->
          put_flash(socket, :error, "Not authenticated")
          socket

        {:error, reason} ->
          Logger.error("Failed to load app '#{inspect(app_name)}'. Reason: #{inspect(reason)}")

          put_flash(socket, :error, reason)
          socket
      end

    Process.send_after(self(), :refresh_status, 1000)

    {:noreply, socket}
  end

  @impl true
  def handle_event("restart_vm", params, socket) do
    Logger.info("restart #{inspect(params)}")

    app_name = socket.assigns.app_name
    vm_id = params["value"]

    Logger.info("restarting #{app_name} #{vm_id}")

    case Client.restart_vm(app_name, vm_id, socket.assigns.config) do
      {:ok, _} ->
        socket

      {:error, :unauthorized} ->
        put_flash(socket, :error, "Not authenticated")

      {:error, reason} ->
        Logger.error("Failed to restart vm '#{inspect(app_name)}'. Reason: #{inspect(reason)}")

        put_flash(socket, :error, reason)
    end

    {:noreply, socket}
  end

  def handle_event("stop_vm", params, socket) do
    Logger.info("stop #{inspect(params)}")

    app_name = socket.assigns.app_name
    vm_id = params["value"]

    Logger.info("stoping #{app_name} #{vm_id}")

    case Client.stop_vm(app_name, vm_id, socket.assigns.config) do
      {:ok, _} ->
        socket

      {:error, :unauthorized} ->
        put_flash(socket, :error, "Not authenticated")

      {:error, reason} ->
        Logger.error("Failed to stop vm '#{inspect(app_name)}'. Reason: #{inspect(reason)}")

        put_flash(socket, :error, reason)
    end

    {:noreply, socket}
  end

  def status_bg_color(app) do
    case app["status"] do
      "running" -> "bg-green-100"
      "dead" -> "bg-red-100"
      _ -> "bg-yellow-100"
    end
  end

  def status_text_color(app) do
    case app["status"] do
      "running" -> "text-green-800"
      "dead" -> "text-red-800"
      _ -> "text-yellow-800"
    end
  end

  def preview_url(app) do
    "https://#{app["name"]}.fly.dev"
  end

  def vm_status_classes(vm) do
    case {vm["transitioning"], vm["status"], vm["healthy"]} do
      {true, _, _} ->
        "animate-spin text-yellow-700"

      {_, "running", true} ->
        "text-green-700"

      {_, "running", false} ->
        "text-yellow-700"

      {_, "pending", _} ->
        "text-yellow-700"

      {_, "stopped", _} ->
        "text-gray-500"

      _ ->
        "text-red-700"
    end
  end

  def vm_status_icon(vm) do
    case {vm["transitioning"], vm["status"], vm["healthy"]} do
      {true, _, _} ->
        :refresh

      {_, "running", true} ->
        :check_circle

      {_, "running", false} ->
        :warning_circle

      {_, "pending", _} ->
        :clock_circle

      {_, "stopped", _} ->
        :minus_circle

      _ ->
        :exclamation_circle
    end
  end

  def health_check_summary(vm) do
    build_msg = fn msg, name, count ->
      if count > 0 do
        "#{msg}#{name}: #{count} "
      else
        msg
      end
    end

    ""
    |> build_msg.("total", vm["totalCheckCount"])
    |> build_msg.("passing", vm["passingCheckCount"])
    |> build_msg.("warn", vm["warningCheckCount"])
    |> build_msg.("critical", vm["criticalCheckCount"])
  end
end
