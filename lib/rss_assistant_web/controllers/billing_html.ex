defmodule RssAssistantWeb.BillingHTML do
  @moduledoc """
  This module contains pages rendered by BillingController.

  See the `billing_html` directory for all templates available.
  """
  use RssAssistantWeb, :html

  embed_templates "billing_html/*"
end
