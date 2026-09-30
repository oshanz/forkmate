defmodule ForkmateWeb.Storybook do
  @moduledoc false
  use PhoenixStorybook,
    otp_app: :forkmate,
    content_path: Path.expand("../../storybook", __DIR__),
    css_path: "/assets/css/storybook.css",
    js_path: "/assets/js/storybook.js",
    sandbox_class: "forkmate"
end
