# frozen_string_literal: true

require "rails_helper"

# The Google One Tap "no account" suppression flag is cleared while signed in so
# the prompt returns after a sign-out. That clearing controller (one-tap-reset)
# is mounted on the <body> via ChromeHead#body_controllers — but ONLY when signed
# in, so it can't wipe the flag on the logged-out /login?via=google bridge page
# (which would re-introduce the auto_select redirect loop). These specs pin that
# logged-in vs logged-out gating.
RSpec.describe "Google One Tap body wiring" do
  it "does not mount one-tap-reset when logged out" do
    visit "/login"

    controllers = page.first("body")["data-controller"]
    expect(controllers).to include("theme")
    expect(controllers).not_to include("one-tap-reset")
  end

  it "mounts one-tap-reset when signed in" do
    user = create(:user)
    move = create(:move, created_by: user) # creator → admin member
    login_as(user: user)
    stub_current_tenant("acme")

    visit move_menu_path(move)

    controllers = page.first("body")["data-controller"]
    expect(controllers).to include("one-tap-reset")
  end
end
