require Logger

defmodule Octoalert do
  @electricity_prices_url "https://api.octopus.energy/v1/products/SILVER-24-07-01/electricity-tariffs/E-1R-SILVER-24-07-01-A/standard-unit-rates/?page_size=1500"
  @gas_prices_url "https://api.octopus.energy/v1/products/SILVER-24-07-01/gas-tariffs/G-1R-SILVER-24-07-01-A/standard-unit-rates/?page_size=1500"
  @discord_notification_url System.get_env("DISCORD_NOTIFICATION_URL") || ""

  def start(_type, _args) do
    main()
    {:ok, self()}
  end

  def main do
    date_to_fetch = Date.utc_today() |> Date.add(1)

    with {:ok, {electric_price, gas_price}} <- fetch_prices(date_to_fetch),
         {:ok} <- notify(electric_price, gas_price) do
      Logger.info("Successfully notified of tomorrow's prices.")
    else
      {:error, error} ->
        Logger.error("Failed to notify of tomorrow's prices.", metadata: %{error: error})
    end
  end

  defp fetch_prices(date) do
    with {:ok, %{"results" => [%{"value_inc_vat" => electric_price} | _]}} <-
           fetch_fuel_prices(@electricity_prices_url, date),
         {:ok, %{"results" => [%{"value_inc_vat" => gas_price} | _]}} <-
           fetch_fuel_prices(@gas_prices_url, date) do
      {:ok, {Float.round(electric_price, 2), Float.round(gas_price, 2)}}
    else
      {:error, error} ->
        {:error, error}

      _ ->
        {:error, nil}
    end
  end

  defp fetch_fuel_prices(url, date) do
    url = build_url_with_filters(url, date)

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, error} ->
        {:error, error}
    end
  end

  defp build_url_with_filters(base_url, date) do
    period_from = NaiveDateTime.new!(date, ~T[00:00:00]) |> NaiveDateTime.to_iso8601()
    period_to = NaiveDateTime.new!(date, ~T[23:59:59]) |> NaiveDateTime.to_iso8601()

    "#{base_url}&period_from=#{period_from}&period_to=#{period_to}"
  end

  defp notify(electric_price, gas_price) do
    body = %{
      "username" => "Octopus Tracker Alerts",
      "content" =>
        "Tomorrow's electricity price is #{electric_price}p. Tomorrow's gas price is #{gas_price}p."
    }

    headers = %{
      "Content-Type" => "application/json"
    }

    response =
      Req.post(
        @discord_notification_url,
        headers: headers,
        body: Jason.encode!(body)
      )

    case response do
      {:ok, %{status: 204}} -> {:ok}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, error} -> {:error, error}
    end
  end
end
