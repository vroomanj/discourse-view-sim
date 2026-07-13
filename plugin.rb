# frozen_string_literal: true

# name: discourse-view-sim
# about: Internal endpoint to bump topic view counts for a fully-disclosed AI research forum.
# version: 0.1.0
# authors: forum_net
# url: https://github.com/vroomanj/discourse-view-sim

enabled_site_setting :view_sim_enabled

after_initialize do
  module ::ViewSim
    PLUGIN_NAME = "discourse-view-sim"

    class Engine < ::Rails::Engine
      engine_name "discourse_view_sim"
      isolate_namespace ViewSim
    end
  end

  # A tiny machine-to-machine endpoint that increments a topic's view counter
  # directly. This intentionally bypasses Discourse's browser-only view
  # tracking (which cannot be triggered by an HTTP client) so a disclosed,
  # owner-operated agent can simulate views in real time. It is authenticated by
  # a shared secret header, NOT a user session.
  class ViewSim::ViewsController < ::ApplicationController
    requires_plugin ViewSim::PLUGIN_NAME

    # No session, CSRF, XHR, or login gates: auth is the shared secret below.
    skip_before_action :verify_authenticity_token,
                       :redirect_to_login_if_required,
                       :check_xhr,
                       raise: false

    def bump
      secret = SiteSetting.view_sim_secret.to_s
      provided = request.headers["X-View-Sim-Secret"].to_s
      if secret.blank? ||
         !ActiveSupport::SecurityUtils.secure_compare(secret, provided)
        raise Discourse::InvalidAccess
      end

      # Abuse guard: cap requests per IP per minute even if the secret leaks.
      RateLimiter.new(
        nil,
        "view-sim-#{request.remote_ip}",
        SiteSetting.view_sim_max_bumps_per_minute,
        1.minute,
      ).performed!

      topic = Topic.find_by(id: params[:topic_id].to_i)
      raise Discourse::NotFound if topic.nil? || topic.archetype != Archetype.default

      count = params[:count].to_i
      count = 1 if count <= 0
      count = 50 if count > 50 # sanity cap per call

      # count is an integer (to_i + clamp), so string interpolation is safe here.
      Topic.where(id: topic.id).update_all("views = views + #{count}")

      render json: { topic_id: topic.id, added: count, views: topic.reload.views }
    end
  end

  ViewSim::Engine.routes.draw { post "/bump/:topic_id" => "views#bump" }

  Discourse::Application.routes.append do
    mount ::ViewSim::Engine, at: "/view-sim"
  end
end
