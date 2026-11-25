# frozen_string_literal: true

require "rails_helper"

# Behavioural coverage for the camera-capture upload lock and its recovery
# state machine (#620/#622, #624). capture_spec.rb only asserts the HTML
# wiring; these examples drive the live Stimulus controller in a real browser
# through the same DOM events its data-action wiring listens to:
#
#   change (photo picked)        → lock raised, pre-submit failsafe (30s) armed
#   turbo:submit-start           → live submission recorded, swapped to the
#                                  in-flight recovery tier (120s)
#   turbo:submit-end (live)      → settle: unlock + camera-capture:settle reset
#   failsafe expiry              → recovery: stop() the live submission, remember
#                                  it as abandoned, settle
#   turbo:submit-end (zombie)    → ignored — must not unlock or reset a newer
#                                  capture, pre-submit or in flight
#
# The harness (harness_js) needs no app changes: it intercepts only the
# failsafe-length timers (>= 30s) so a spec can expire a tier on demand while
# every short timer (downscale race, flash, Turbo) runs for real; it stubs the
# form's requestSubmit so a picked photo stays in the pre-submit window until
# the spec emits Turbo's lifecycle events itself, with fake FormSubmission
# objects whose identity and stop() calls it can observe. The last example
# runs the real Turbo submission end to end instead.
#
# `:js` specs run in CI only (no chromedriver in the dev container). The
# tenant/host setup mirrors capture_and_autosave_js_spec.rb.
RSpec.describe "Capture upload lock recovery (JS)", :js do
  let(:slug) { "jslock" }
  let(:user) { create(:user) }
  let(:image) { Rails.root.join("spec/fixtures/files/sample_image.png") }
  let!(:move_and_box) do
    Apartment::Tenant.switch(slug) do
      move = create(:move, created_by: user)
      [move, create(:box, move:, number: "1", status: "packing")]
    end
  end

  # The tile is the lock's visible face: #setState renders it inert while an
  # upload is pending (guardPick is the functional block, probed separately).
  def fallback_tile = "[data-camera-capture-target='fallback']"
  def locked_tile = "#{fallback_tile}.pointer-events-none.opacity-50"
  def unlocked_tile = "#{fallback_tile}:not(.pointer-events-none):not(.opacity-50)"

  # Mirrors camera_capture_controller.js (defaults unchanged, not injectable).
  def settle_failsafe_ms = 30_000
  def inflight_recovery_ms = 120_000

  # stub_submit: hold a picked photo in the pre-submit window (the spec then
  # emits Turbo's lifecycle events itself); false lets the form submit for real.
  def harness_js(stub_submit: true)
    <<~JS
      (() => {
        if (window.__lockHarness) return
        const realSet = window.setTimeout.bind(window)
        const realClear = window.clearTimeout.bind(window)
        const pending = new Map()
        let seq = 0
        window.setTimeout = (fn, ms, ...args) => {
          if (typeof ms === "number" && ms >= #{settle_failsafe_ms}) {
            const handle = `lock-timer-${++seq}`
            pending.set(handle, { fn, ms, args })
            return handle
          }
          return realSet(fn, ms, ...args)
        }
        window.clearTimeout = (handle) => { if (!pending.delete(handle)) realClear(handle) }

        const form = document.querySelector("form[data-controller~='capture-upload']")
        const input = form.querySelector("[data-camera-capture-target='input']")
        const submissions = {}
        const harness = window.__lockHarness = {
          settles: 0,
          submitRequests: 0,
          pendingDelays: () => [...pending.values()].map((t) => t.ms).sort((a, b) => a - b),
          expire(ms) {
            let fired = 0
            for (const [handle, timer] of [...pending]) {
              if (timer.ms !== ms) continue
              pending.delete(handle)
              timer.fn(...timer.args)
              fired++
            }
            return fired
          },
          pick(name) {
            const transfer = new DataTransfer()
            transfer.items.add(new File([new Uint8Array([1, 2, 3])], name, { type: "image/jpeg" }))
            input.files = transfer.files
            input.dispatchEvent(new Event("change", { bubbles: true }))
          },
          cancelPick() {
            input.value = ""
            input.dispatchEvent(new Event("change", { bubbles: true }))
          },
          // kind: "normal" (stop() works), "throwing" (stop() raises), "legacy" (no stop()).
          submission(name, kind) {
            const sub = { name, stops: 0 }
            if (kind !== "legacy") {
              sub.stop = function () {
                this.stops++
                if (kind === "throwing") throw new Error("stop failed")
              }
            }
            submissions[name] = sub
          },
          submitStart(name) {
            form.dispatchEvent(new CustomEvent("turbo:submit-start",
              { bubbles: true, detail: { formSubmission: submissions[name] } }))
          },
          submitEnd(name) {
            const detail = name ? { formSubmission: submissions[name] } : {}
            form.dispatchEvent(new CustomEvent("turbo:submit-end", { bubbles: true, detail }))
          },
          stops: (name) => submissions[name].stops,
          fileName: () => input.files[0]?.name || "",
          pickBlocked() {
            const click = new MouseEvent("click", { bubbles: true, cancelable: true })
            input.dispatchEvent(click)
            return click.defaultPrevented
          }
        }
        if (#{stub_submit}) form.requestSubmit = () => { harness.submitRequests++ }
        form.addEventListener("camera-capture:settle", () => { harness.settles++ })
      })()
    JS
  end

  around do |example|
    original_zone = Rails.application.config.x.tenant_zone
    original_app_host = Capybara.app_host
    original_include_port = Capybara.always_include_port

    Rails.application.config.x.tenant_zone = "lvh.me"
    Capybara.app_host = "http://#{slug}.lvh.me"
    Capybara.always_include_port = true

    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Organizations::Create.new.call(name: "JS Lock Org", slug: slug, owner: user).value!

    example.run
  ensure
    Apartment::Tenant.drop(slug) if Apartment.tenant_names.include?(slug)
    Rails.application.config.x.tenant_zone = original_zone
    Capybara.app_host = original_app_host
    Capybara.always_include_port = original_include_port
  end

  def visit_capture
    move, box = move_and_box
    login_as(user: user)
    visit move_box_capture_path(move, box)
    expect(page).to have_text(I18n.t("captures.tap_to_capture"))
    wait_for_controller
  end

  def wait_for_controller
    wait_until("camera-capture to connect") do
      page.evaluate_script(<<~JS)
        !!window.Stimulus?.getControllerForElementAndIdentifier(
          document.querySelector("[data-controller='camera-capture']"), "camera-capture")
      JS
    end
  end

  # Retry a browser-side condition within Capybara's wait time.
  def wait_until(what)
    page.document.synchronize do
      raise Capybara::ExpectationNotMet, "timed out waiting for #{what}" unless yield
    end
  end

  def install_harness
    page.execute_script(harness_js)
  end

  def harness(call)
    page.evaluate_script("window.__lockHarness.#{call}")
  end

  def harness!(call)
    page.execute_script("window.__lockHarness.#{call}")
  end

  def expect_locked
    expect(page).to have_css(locked_tile)
    expect(harness("pickBlocked()")).to be(true)
  end

  def expect_unlocked
    expect(page).to have_css(unlocked_tile)
    expect(harness("pickBlocked()")).to be(false)
  end

  # Abandon `name` through the in-flight recovery tier: picked → in flight → 120s.
  def abandon_in_flight(name, kind: "normal")
    harness!("submission('#{name}', '#{kind}')")
    harness!("pick('#{name}.jpg')")
    harness!("submitStart('#{name}')")
    expect(harness("expire(#{inflight_recovery_ms})")).to eq(1)
  end

  context "with the lifecycle driven by synthetic Turbo events" do
    before do
      visit_capture
      install_harness
    end

    it "starts unlocked with no failsafe armed" do
      expect_unlocked
      expect(harness("pendingDelays()")).to eq([])
    end

    it "does not lock on a cancelled picker (change with an empty selection)" do
      harness!("cancelPick()")

      expect_unlocked
      expect(harness("pendingDelays()")).to eq([])
    end

    it "raises the lock and arms only the pre-submit failsafe when a photo is picked" do
      harness!("pick('first.jpg')")

      expect_locked
      expect(harness("pendingDelays()")).to eq([settle_failsafe_ms])
      expect(harness("fileName()")).to eq("first.jpg")
    end

    it "keeps the lock while capture-upload is pre-submit, then recovers on failsafe expiry" do
      harness!("pick('first.jpg')")
      # capture-upload has called requestSubmit (stubbed): no Turbo terminal
      # event will ever come, so only the pre-submit tier can release the lock.
      wait_until("capture-upload to request the submit") { harness("submitRequests").positive? }
      expect_locked

      expect(harness("expire(#{settle_failsafe_ms})")).to eq(1)

      expect_unlocked
      expect(harness("settles")).to eq(1)
      expect(harness("fileName()")).to eq("")
      expect(harness("pendingDelays()")).to eq([])
    end

    it "swaps the pre-submit failsafe for the in-flight tier on turbo:submit-start" do
      harness!("submission('a', 'normal')")
      harness!("pick('a.jpg')")
      harness!("submitStart('a')")

      expect(harness("pendingDelays()")).to eq([inflight_recovery_ms])
      # The cleared pre-submit timer can't fire mid-flight.
      expect(harness("expire(#{settle_failsafe_ms})")).to eq(0)
      expect_locked
      expect(harness("settles")).to eq(0)
    end

    it "ignores turbo:submit-start when no upload is pending" do
      harness!("submission('a', 'normal')")
      harness!("submitStart('a')")

      expect_unlocked
      expect(harness("pendingDelays()")).to eq([])
    end

    it "settles on the live submission's turbo:submit-end without aborting it" do
      harness!("submission('a', 'normal')")
      harness!("pick('a.jpg')")
      harness!("submitStart('a')")
      harness!("submitEnd('a')")

      expect_unlocked
      expect(harness("settles")).to eq(1)
      expect(harness("fileName()")).to eq("")
      expect(harness("pendingDelays()")).to eq([])
      expect(harness("stops('a')")).to eq(0)
    end

    it "settles on a turbo:submit-end that carries no formSubmission detail" do
      harness!("submission('a', 'normal')")
      harness!("pick('a.jpg')")
      harness!("submitStart('a')")
      harness!("submitEnd()")

      expect_unlocked
      expect(harness("settles")).to eq(1)
      expect(harness("pendingDelays()")).to eq([])
    end

    it "ignores a foreign submission's turbo:submit-end while the live one is in flight" do
      harness!("submission('a', 'normal')")
      harness!("submission('stranger', 'normal')")
      harness!("pick('a.jpg')")
      harness!("submitStart('a')")
      harness!("submitEnd('stranger')")

      expect_locked
      expect(harness("settles")).to eq(0)
      expect(harness("fileName()")).to eq("a.jpg")
      expect(harness("pendingDelays()")).to eq([inflight_recovery_ms])
    end

    it "aborts the hung submission and unlocks when the in-flight tier expires" do
      abandon_in_flight("a")

      expect(harness("stops('a')")).to eq(1)
      expect_unlocked
      expect(harness("settles")).to eq(1)
      expect(harness("fileName()")).to eq("")
      expect(harness("pendingDelays()")).to eq([])
    end

    # The Release Bug Scan's check: expire a stalled submission, start another
    # capture, then emit the abandoned submission's terminal event.
    it "keeps a newer pre-submit capture's input and lock when the zombie's terminal event arrives" do
      abandon_in_flight("a")
      harness!("pick('b.jpg')")
      expect_locked

      harness!("submitEnd('a')")

      expect_locked
      expect(harness("fileName()")).to eq("b.jpg")
      expect(harness("settles")).to eq(1) # only the recovery's own settle
      expect(harness("pendingDelays()")).to eq([settle_failsafe_ms])

      # The newer capture's own lifecycle still settles normally.
      harness!("submission('b', 'normal')")
      harness!("submitStart('b')")
      harness!("submitEnd('b')")
      expect_unlocked
      expect(harness("settles")).to eq(2)
    end

    it "keeps a newer in-flight capture's lock when the zombie's terminal event arrives" do
      abandon_in_flight("a")
      harness!("submission('b', 'normal')")
      harness!("pick('b.jpg')")
      harness!("submitStart('b')")

      harness!("submitEnd('a')")

      expect_locked
      expect(harness("fileName()")).to eq("b.jpg")
      expect(harness("pendingDelays()")).to eq([inflight_recovery_ms])

      harness!("submitEnd('b')")
      expect_unlocked
    end

    it "still ignores a repeated zombie terminal event after the abandoned entry is consumed" do
      abandon_in_flight("a")
      harness!("submitEnd('a')") # the abort's own terminal event consumes the entry
      harness!("submission('b', 'normal')")
      harness!("pick('b.jpg')")
      harness!("submitStart('b')")

      harness!("submitEnd('a')") # now caught by the live-submission demux

      expect_locked
      expect(harness("fileName()")).to eq("b.jpg")
    end

    it "remembers every zombie across a later pre-submit recovery (a set, not a slot)" do
      abandon_in_flight("a")
      # B never reaches submit-start: its pre-submit recovery has no live
      # submission and must not erase A's identity.
      harness!("pick('b.jpg')")
      expect(harness("expire(#{settle_failsafe_ms})")).to eq(1)
      abandon_in_flight("c")
      harness!("pick('d.jpg')")

      harness!("submitEnd('a')")
      harness!("submitEnd('c')")

      expect_locked
      expect(harness("fileName()")).to eq("d.jpg")
      expect(harness("settles")).to eq(3) # A's, B's and C's recoveries only
      expect(harness("pendingDelays()")).to eq([settle_failsafe_ms])
    end

    it "still recovers, and still ignores the zombie, when stop() raises" do
      abandon_in_flight("a", kind: "throwing")

      expect(harness("stops('a')")).to eq(1)
      expect_unlocked

      harness!("pick('b.jpg')")
      harness!("submitEnd('a')")
      expect_locked
      expect(harness("fileName()")).to eq("b.jpg")
    end

    it "still recovers, and still ignores the zombie, when the submission has no stop()" do
      abandon_in_flight("a", kind: "legacy")

      expect_unlocked

      harness!("pick('b.jpg')")
      harness!("submitEnd('a')")
      expect_locked
      expect(harness("fileName()")).to eq("b.jpg")
    end

    it "clears the armed failsafe when the controller disconnects" do
      harness!("pick('a.jpg')")
      expect(harness("pendingDelays()")).to eq([settle_failsafe_ms])

      page.execute_script(<<~JS)
        document.querySelector("[data-controller='camera-capture']").removeAttribute("data-controller")
      JS

      # Stimulus disconnects on its MutationObserver tick, not synchronously.
      wait_until("the failsafe to be cleared") { harness("pendingDelays()").empty? }
      expect(harness("pendingDelays()")).to eq([])
    end
  end

  context "with a real Turbo submission" do
    # Form-level listeners run before the wrapper's camera-capture actions
    # (bubbling), so submit-end sees the timer the real submit-start armed.
    def record_real_submission
      page.execute_script(<<~JS)
        const form = document.querySelector("form[data-controller~='capture-upload']")
        const tile = document.querySelector("#{fallback_tile}")
        window.__real = {}
        form.addEventListener("turbo:submit-start", (e) => {
          window.__real.lockedAtStart = tile.classList.contains("pointer-events-none")
          window.__real.stopIsFunction = typeof e.detail.formSubmission?.stop === "function"
        })
        form.addEventListener("turbo:submit-end", () => {
          window.__real.delaysAtEnd = window.__lockHarness.pendingDelays()
        })
      JS
    end

    it "holds the lock in flight on the in-flight tier, then settles and resets on the real submit-end" do
      visit_capture
      # Only the timer interception — the form submits for real here.
      page.execute_script(harness_js(stub_submit: false))
      record_real_submission

      attach_file("file", image, make_visible: true)

      wait_until("the real submission to settle the lock") { harness("settles") == 1 }
      expect_unlocked
      # The photo persisted: the response renders its card into the session panel.
      move, box = move_and_box
      expect(page).to have_css(%(a[href*="/moves/#{move.id}/boxes/#{box.id}/review/photo"]))
      expect(harness("settles")).to eq(1)
      expect(harness("fileName()")).to eq("")
      expect(harness("pendingDelays()")).to eq([])
      real = page.evaluate_script("window.__real")
      expect(real).to eq("lockedAtStart" => true, "stopIsFunction" => true,
                         "delaysAtEnd" => [inflight_recovery_ms])
    end
  end
end
