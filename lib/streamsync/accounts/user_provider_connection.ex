defmodule Streamsync.Accounts.UserProviderConnection do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_provider_connections" do
    field :provider, :string
    field :provider_email, :string
    field :provider_uid, :string
    field :access_token, :string, redact: true
    field :refresh_token, :string, redact: true
    field :expires_at, :utc_datetime

    belongs_to :user, Streamsync.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  A changeset for creating or updating a user provider connection.
  """
  def changeset(user_provider_connection, attrs) do
    user_provider_connection
    |> cast(attrs, [
      :provider,
      :provider_uid,
      :provider_email,
      :access_token,
      :refresh_token,
      :expires_at,
      :user_id
    ])
    |> validate_required([:provider, :provider_email, :user_id])
    |> validate_format(:provider_email, ~r/^[^\s]+@[^\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> unique_constraint([:provider, :provider_email], name: :unique_provider_email_per_user)
  end
end
