class CommentsController < ApplicationController
  include CommentRateLimit

  before_action :enforce_comment_budget, only: :create

  def create
    plugin = find_plugin
    comment = plugin.comments.new(user: Current.user, body: params[:body])
    if comment.save
      redirect_to plugin_path(plugin.publisher.name, plugin.name), notice: "Comment posted."
    else
      redirect_to plugin_path(plugin.publisher.name, plugin.name), alert: comment.errors.full_messages.join("; ")
    end
  end

  # Authors delete their own comments; moderation (hiding others') lives in the
  # MFA-gated admin controllers and always leaves an audit trail.
  def destroy
    comment = Current.user.comments.find(params[:id])
    comment.destroy!
    redirect_back fallback_location: root_path, notice: "Comment removed."
  end

  private

  # Shared with the client API, so posting through an app is not the cheap way
  # around the form's limit.
  def enforce_comment_budget
    return unless comment_budget_exceeded?
    redirect_back fallback_location: root_path, alert: "Slow down — try again in a bit."
  end

  def find_plugin
    Publisher.find_by!(name: params[:publisher]).plugins.find_by!(name: params[:name])
  end
end
