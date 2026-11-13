defmodule Retrobeam.Retros.JoinCode do
  @moduledoc """
  Join codes for retros.

  A join code is 6 characters from an alphabet without look-alikes (no 0, O,
  1, I or L), so it is easy to read aloud and type. Codes are stored
  uppercase and matched case-insensitively.
  """

  @alphabet ~c"ABCDEFGHJKMNPQRSTUVWXYZ23456789"
  @length 6

  @doc "The characters a join code may contain."
  def alphabet, do: List.to_string(@alphabet)

  @doc "The number of characters in a join code."
  def length, do: @length

  @doc """
  Generates a random join code.

      iex> code = Retrobeam.Retros.JoinCode.generate()
      iex> Retrobeam.Retros.JoinCode.valid?(code)
      true
  """
  def generate do
    alphabet = List.to_tuple(@alphabet)
    size = tuple_size(alphabet)

    for <<byte <- :crypto.strong_rand_bytes(@length)>>, into: "" do
      <<elem(alphabet, rem(byte, size))>>
    end
  end

  @doc """
  Normalizes user input: trims surrounding whitespace and upcases.

      iex> Retrobeam.Retros.JoinCode.normalize("  abc234 ")
      "ABC234"
  """
  def normalize(code) when is_binary(code), do: code |> String.trim() |> String.upcase()
  def normalize(_code), do: ""

  @doc """
  Returns true when `code` (already normalized) has the join code format.

      iex> Retrobeam.Retros.JoinCode.valid?("ABC234")
      true
      iex> Retrobeam.Retros.JoinCode.valid?("ABC10O")
      false
  """
  def valid?(code) when is_binary(code) do
    byte_size(code) == @length and
      code |> String.to_charlist() |> Enum.all?(&(&1 in @alphabet))
  end

  def valid?(_code), do: false
end
