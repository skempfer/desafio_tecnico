defmodule WCore.Mailer do
  @moduledoc """
  Mailer wrapper for outbound emails.

  Uses Swoosh and the application mailer configuration.
  """

  use Swoosh.Mailer, otp_app: :w_core
end
