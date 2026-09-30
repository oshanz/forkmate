defmodule ForkmateWeb.PageController do
  use ForkmateWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
