// Shared sessionStorage key for the Google One Tap "no account" suppression
// flag. Imported by google_one_tap_controller (sets it on no_account, clears it
// on a successful sign-in) and one_tap_reset_controller (clears it on signed-in
// pages) so the two can't silently drift. Not a Stimulus controller —
// eagerLoadControllersFrom only registers files ending in "_controller".
export const NO_ACCOUNT_KEY = "google_one_tap_no_account"
