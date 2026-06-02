# frozen_string_literal: true

class RodauthApp < Rodauth::Rails::App
  unless BuildTasks.assets_precompile?
    configure RodauthMain

    route do |r|
      rodauth.load_memory
      r.rodauth
    end
  end
end
