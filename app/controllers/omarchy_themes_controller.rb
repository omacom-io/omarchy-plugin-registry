class OmarchyThemesController < ApplicationController
  allow_unauthenticated_access

  def show
    return head :not_found unless request.local?

    theme = Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)
    return head :no_content unless theme

    response.headers["Cache-Control"] = "no-store"
    render json: theme
  end
end
