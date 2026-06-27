# frozen_string_literal: true

# The legal "Terms of Use & Risk Acknowledgement" every account must accept
# before using the app (#369). `CURRENT_VERSION` is the version a fresh
# acceptance records and the gate (TenantController#require_terms_agreement!)
# checks against — bump it when the terms change to re-gate every account (the
# future re-agreement flow, for free). Keeping the version and the copy together
# means a later versioned-content system can switch both in lock-step.
#
# NOTE: `SECTIONS`/`INTRO` are DRAFT placeholder wording while the legal
# framework is being put in place — replace with the final reviewed text (and
# bump `CURRENT_VERSION` + `EFFECTIVE_DATE` when you do).
module Terms
  # Date-stamped version of the live terms. Bumping this re-gates all accounts.
  CURRENT_VERSION = "2026-06-27"

  # Human-readable effective date shown to the user; tracks CURRENT_VERSION.
  EFFECTIVE_DATE = "27 June 2026"

  TITLE = "Terms of Use & Risk Acknowledgement"

  INTRO =
    "This service is provided free of charge and is under active development. " \
    "By creating an account and using it, you acknowledge and accept the risks " \
    "set out below. Please read them before continuing."

  # Each entry renders as a titled paragraph on the interstitial.
  SECTIONS = [
    {
      heading: "Active development — expect change and disruption",
      body:
        "Features may change, break, or be removed without notice. The service " \
        "may be unavailable, reset, or behave unexpectedly at any time as we " \
        "continue to build it."
    },
    {
      heading: "No legal framework yet",
      body:
        "The legal terms, privacy framework, and data-processing agreements for " \
        "this service are still being put in place. Until they are, the service " \
        "is offered on an as-is, best-effort basis with no warranties of any kind."
    },
    {
      heading: "No guaranteed backup or recovery",
      body:
        "Backup and recovery are not yet guaranteed. Your data may be lost, " \
        "corrupted, or deleted, and we may not be able to recover it. Do not " \
        "store anything you cannot afford to lose, and keep your own copies of " \
        "anything important."
    },
    {
      heading: "Use at your own risk",
      body:
        "You use this service entirely at your own risk. To the fullest extent " \
        "permitted by law, we accept no liability for any loss or damage arising " \
        "from your use of it. You can stop using it and delete your account at " \
        "any time."
    }
  ].freeze
end
