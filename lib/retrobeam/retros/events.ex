defmodule Retrobeam.Retros.Events do
  @moduledoc """
  PubSub topics and broadcast helpers for retros.

  `Retrobeam.Retros.RetroServer` broadcasts on `topic/1` after each change is
  written to Postgres, and every `RetrobeamWeb.RetroLive.Show` subscribes to
  it. Events are plain tagged tuples; the stories that add a change add its
  event shape here, so the server and the LiveView agree on it.
  """

  @pubsub Retrobeam.PubSub

  @typedoc "An event broadcast on a retro's topic."
  @type t :: term()

  @doc "The topic for everything that changes a retro's board."
  def topic(retro_id), do: "retro:#{retro_id}"

  @doc "The topic for Phoenix.Presence on a retro."
  def presence_topic(retro_id), do: "retro:#{retro_id}:presence"

  @doc "The topic for events only the facilitator should see."
  def facilitator_topic(retro_id), do: "retro:#{retro_id}:facilitator"

  @doc "Subscribes the calling process to a retro's board events."
  def subscribe(retro_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(retro_id))

  @doc "Broadcasts `event` to everyone subscribed to the retro."
  @spec broadcast(integer(), t()) :: :ok | {:error, term()}
  def broadcast(retro_id, event), do: Phoenix.PubSub.broadcast(@pubsub, topic(retro_id), event)
end
