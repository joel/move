# frozen_string_literal: true

module Components
  class GoogleOneTap < Components::Base
    def view_template
      return unless show?

      div(
        data: {
          controller: "google-one-tap",
          google_one_tap_client_id_value: ENV.fetch("GOOGLE_CLIENT_ID", nil),
          google_one_tap_login_path_value: "/auth/google/one_tap"
        },
        style: "display:none"
      )
    end

    private

    # Only prompt on the apex (public tenant): FedCM uses the page origin, and
    # only the apex (move-easy.org) is a registered Google JS origin — on an org
    # subdomain One Tap would fail with an origin error. The component renders in
    # the global layout, so it must guard the host itself.
    def show?
      ENV["GOOGLE_CLIENT_ID"].present? &&
        Apartment::Tenant.current == Apartment.default_tenant &&
        !view_context.rodauth.logged_in?
    end
  end
end
