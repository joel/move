# frozen_string_literal: true

module Webauthn
  module NameSuggester
    DEFAULT = "Passkey"
    MAX_LENGTH = 60

    module_function

    def from_user_agent(user_agent)
      label = detect_label(user_agent.to_s)
      label.to_s[0, MAX_LENGTH]
    end

    PATTERNS = [
      [/iPhone/i,     ->(_) { "iPhone" }],
      [/iPad/i,       ->(_) { "iPad" }],
      [/Macintosh/i,  ->(ua) { mac_label(ua) }],
      [/Android/i,    ->(ua) { android_label(ua) }],
      [/Windows NT/i, ->(_) { "Windows PC" }],
      [/CrOS/i,       ->(_) { "Chromebook" }],
      [/Linux/i,      ->(_) { "Linux device" }]
    ].freeze

    def detect_label(user_agent)
      return DEFAULT if user_agent.empty?

      _, resolver = PATTERNS.find { |pattern, _| user_agent.match?(pattern) }
      resolver ? resolver.call(user_agent) : DEFAULT
    end

    def mac_label(user_agent)
      return "Mac (Edge)" if user_agent.match?(%r{Edg/}i)
      return "Mac (Chrome)" if user_agent.match?(/Chrome/i)
      return "Mac (Firefox)" if user_agent.match?(/Firefox/i)
      return "Mac (Safari)" if user_agent.match?(/Safari/i)

      "Mac"
    end

    def android_label(user_agent)
      return "Pixel phone" if user_agent.match?(/Pixel/i)

      "Android phone"
    end
  end
end
