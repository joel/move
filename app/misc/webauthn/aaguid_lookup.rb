# frozen_string_literal: true

module Webauthn
  # AAGUID → authenticator name.
  #
  # Curated subset of the public
  # https://github.com/passkeydeveloper/passkey-authenticator-aaguids
  # registry — only the entries most likely to show up on the passkeys
  # our user base actually uses. Add entries as they come up.
  module AaguidLookup
    REGISTRY = {
      "adce0002-35bc-c60a-648b-0b25f1f05503" => "Chrome on Mac",
      "dd4ec289-e01d-41c9-bb89-70fa845d4bf2" => "iCloud Keychain (iOS)",
      "fbfc3007-154e-4ecc-8c0b-6e020557d7bd" => "iCloud Keychain",
      "ea9b8d66-4d01-1d21-3ce4-b6b48cb575d4" => "Google Password Manager",
      "08987058-cadc-4b81-b6e1-30de50dcbe96" => "Windows Hello",
      "9ddd1817-af5a-4672-a2b9-3e3dd95000a9" => "Windows Hello",
      "b84e4048-15dc-4dd0-8640-f4f60813c8af" => "1Password",
      "bada5566-a7aa-401f-bd96-45619a55120d" => "1Password",
      "d548826e-79b4-db40-a3d8-11116f7e8349" => "Bitwarden",
      "fdb141b2-5d84-443e-8a35-4698c205a502" => "KeePassXC",
      "cc45f64e-52a2-451b-831a-4edd8022a202" => "ToothPic Passkey Provider",
      "b5397666-4885-aa6b-cebf-e52262a439a2" => "Chromium"
    }.freeze

    module_function

    def lookup(aaguid)
      return nil if aaguid.blank?

      key = aaguid.to_s.downcase
      REGISTRY[key]
    end
  end
end
