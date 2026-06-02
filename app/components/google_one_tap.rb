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

    def show?
      ENV["GOOGLE_CLIENT_ID"].present? &&
        !view_context.rodauth.logged_in?
    end
  end
end
