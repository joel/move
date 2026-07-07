require "rails_helper"

RSpec.describe "Captures" do
  let(:user) { create(:user) }
  let(:move) { create(:move, created_by: user) }
  let(:box) { create(:box, move:, number: "1", status: "packing") }

  before do
    stub_current_user(user)
    stub_current_tenant("acme")
  end

  def upload(name = "sample_image.png", type = "image/png")
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files", name), type)
  end

  describe "GET capture" do
    it "renders the capture screen with the unambiguous target box" do
      get move_box_capture_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Capture for Box #001")
      expect(response.body).to include(I18n.t("captures.tap_to_capture"))
    end

    it "excludes AI-generated item images from the capture panel (#416)" do
      # A generated image has no recognition run; in the panel it would otherwise
      # render as a forever-queued row. With only generated media, the panel is empty.
      generated = create(:media, move:, box:, captured_via: "generated")
      create(:item, :manual, move:, box:, source_media: generated, name: "Lamp")

      get move_box_capture_path(move, box)

      expect(response.body).to include(I18n.t("captures.session.empty"))
    end

    it "redirects a sealed box to the box detail (capture blocked)" do
      sealed = create(:box, :with_room, move:, status: "sealed")

      get move_box_capture_path(move, sealed)

      expect(response).to redirect_to(move_box_path(move, sealed))
    end

    # #199 — the `fake` provider returns canned sample detections; warn the user
    # so a fabricated result is never mistaken for real recognition.
    it "shows the demo-mode banner when the provider is fake" do
      get move_box_capture_path(move, box)

      expect(response.body).to include(I18n.t("captures.demo_banner"))
    end

    it "hides the demo-mode banner for a real provider" do
      move.update!(recognition_provider: "openai", openai_api_key: "sk-test")

      get move_box_capture_path(move, box)

      expect(response.body).not_to include(I18n.t("captures.demo_banner"))
    end
  end

  describe "POST capture" do
    it "responds instantly with a pending placeholder tile — ingest is async (#545)" do
      allow(Captures::IngestJob).to receive(:perform_later) # keep the heavy work off this request

      expect do
        post move_box_capture_path(move, box), params: { file: upload },
                                               headers: { "Accept" => "text/vnd.turbo-stream.html" }
      end.to change(box.media.pending, :count).by(1)

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include(Views::Captures::SessionPanel::ID)
      # The count lives inside the replaced panel (#546), so the stream refreshes
      # it — no stale header after upload.
      expect(response.body).to include(I18n.t("captures.session.count", count: 1))
      expect(Captures::IngestJob).to have_received(:perform_later)
    end

    it "captures an image and lands split items once ingest + recognition run" do
      # Test runs jobs inline, so the async ingest completes within the request:
      # IngestJob normalizes/attaches → recognition enqueues + runs.
      expect do
        post move_box_capture_path(move, box), params: { file: upload }
      end.to change(box.media.ready, :count).by(1)

      expect(response).to redirect_to(move_box_capture_path(move, box))
      expect(box.recognition_runs.last.status).to eq("succeeded")
      expect(box.items.where(review_state: "auto_confirmed").count).to eq(2)
      expect(box.items.where(review_state: "pending_review").count).to eq(1)
    end

    it "fails honestly with no file (no offline queue)" do
      post move_box_capture_path(move, box), params: {}

      expect(response).to redirect_to(move_box_capture_path(move, box))
      follow_redirect!
      expect(response.body).to include(I18n.t("captures.errors.no_file"))
    end

    it "transcodes a non-native upload (TIFF) to JPEG and captures it" do
      expect do
        post move_box_capture_path(move, box), params: { file: upload("sample.tiff", "image/tiff") }
      end.to change(box.media, :count).by(1)

      expect(response).to redirect_to(move_box_capture_path(move, box))
      expect(box.media.last.image.content_type).to eq("image/jpeg")
    end

    it "rejects an oversized upload with a clear message" do
      stub_const("Media::MAX_IMAGE_BYTES", 5)
      expect do
        post move_box_capture_path(move, box), params: { file: upload }
      end.not_to change(box.media, :count)

      expect(response).to redirect_to(move_box_capture_path(move, box))
      follow_redirect!
      expect(response.body).to include("too large")
    end

    it "rejects an unsupported image (SVG) with an actionable, specific message" do
      expect do
        post move_box_capture_path(move, box), params: { file: upload("sample.svg", "image/svg+xml") }
      end.not_to change(box.media, :count)

      expect(response).to redirect_to(move_box_capture_path(move, box))
      follow_redirect!
      # Apostrophe-free slice of captures.errors.unsupported_image (the rendered
      # toast HTML-escapes the "isn't" apostrophe).
      expect(response.body).to include("Use a photo (JPEG, PNG, WEBP, HEIC, or TIFF)")
      expect(response.body).not_to include(I18n.t("captures.errors.failed"))
    end
  end

  # #241 — the panel now lives inline on the capture page and updates live over
  # ActionCable (Captures::SessionBroadcastSubscriber); there is no polled endpoint.
  describe "GET capture (session panel renders inline)" do
    it "subscribes to the Box's recognition stream and renders the panel" do
      media = create(:media, move:, box:)
      create(:recognition_run, :succeeded, move:, box:, media:)

      get move_box_capture_path(move, box)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("<turbo-cable-stream-source")
      expect(response.body).to include(%(id="#{Views::Captures::SessionPanel::ID}"))
    end

    it "renders a succeeded photo as one card (names as chips) linking to the photo detail" do
      media = create(:media, move:, box:)
      create(:recognition_run, :succeeded, move:, box:, media:)
      create(:item, move:, box:, name: "Espresso machine", source_media: media)

      get move_box_capture_path(move, box)

      # Photo-first (D3): the card links to the per-photo review/detail, with the
      # item name shown as a chip inside it — not a separate item-detail row.
      expect(response.body).to include(%(href="#{move_box_review_photo_path(move, box, media_id: media.id)}"))
      expect(response.body).to include("Espresso machine")
      expect(response.body).to include('data-turbo-prefetch="false"')
    end

    it "surfaces a friendly reason for a known failure category (quota)" do
      media = create(:media, move:, box:)
      create(:recognition_run, :failed, move:, box:, media:,
                                        error_message: "RecognitionProviders::Openai request failed (429): " \
                                                       "You exceeded your current quota, please check your plan and billing details.")

      get move_box_capture_path(move, box)

      expect(response.body).to include(I18n.t("ui.recognition_errors.quota"))
    end

    it "falls back to the cleaned vendor detail for an unrecognized failure" do
      media = create(:media, move:, box:)
      create(:recognition_run, :failed, move:, box:, media:,
                                        error_message: "RecognitionProviders::Openai request failed (500): The model glitched.")

      get move_box_capture_path(move, box)

      expect(response.body).to include("The model glitched.")
      expect(response.body).not_to include("RecognitionProviders::Openai")
    end

    it "shows the generic line (never the class name) for an internal model-drift error" do
      media = create(:media, move:, box:)
      create(:recognition_run, :failed, move:, box:, media:,
                                        error_message: "RecognitionProviders::Openai returned a 2xx with no objects array")

      get move_box_capture_path(move, box)

      # Apostrophe-free slice of ui.recognition_errors.generic (the rendered HTML
      # escapes the "couldn't" apostrophe).
      expect(response.body).to include("be completed. Please retry.")
      expect(response.body).not_to include("RecognitionProviders::Openai")
    end
  end

  describe "POST capture/retry" do
    it "creates a new run for a failed media" do
      media = create(:media, move:, box:)
      create(:recognition_run, :failed, move:, box:, media:)

      expect do
        post move_box_capture_retry_path(move, box, media_id: media.id)
      end.to change(box.recognition_runs, :count).by(1)
    end
  end

  describe "POST capture/direct_upload (#572 presign)" do
    def blob_params(byte_size: 1234, content_type: "image/jpeg")
      { blob: { filename: "capture.jpg", byte_size:, checksum: Digest::MD5.base64digest("x"),
                content_type: } }
    end

    it "404s when direct upload is disabled (the default in test)" do
      post move_box_capture_direct_upload_path(move, box), params: blob_params, as: :json
      expect(response).to have_http_status(:not_found)
    end

    context "when direct upload is enabled" do
      around do |example|
        previous = Rails.application.config.x.direct_upload_enabled
        Rails.application.config.x.direct_upload_enabled = true
        example.run
        Rails.application.config.x.direct_upload_enabled = previous
      end

      it "returns the presigned PUT and a MOVE-SCOPED signed_id (not the global one)" do
        expect { post move_box_capture_direct_upload_path(move, box), params: blob_params, as: :json }
          .to change(ActiveStorage::Blob, :count).by(1)

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body.dig("direct_upload", "url")).to be_present
        expect(body.dig("direct_upload", "headers")).to be_a(Hash)
        expect(body["signed_id"]).to be_present
        # It is purpose-bound: verifying WITHOUT the Move purpose must fail, proving
        # it isn't Active Storage's global signed_id.
        expect { ActiveStorage::Blob.find_signed!(body["signed_id"]) }
          .to raise_error(ActiveSupport::MessageVerifier::InvalidSignature)
      end

      it "rejects an over-cap byte_size before minting a URL (413)" do
        expect do
          post move_box_capture_direct_upload_path(move, box),
               params: blob_params(byte_size: Media::MAX_IMAGE_BYTES + 1), as: :json
        end.not_to change(ActiveStorage::Blob, :count)
        expect(response).to have_http_status(:content_too_large)
      end

      it "rejects a non-image declared type (415)" do
        post move_box_capture_direct_upload_path(move, box),
             params: blob_params(content_type: "application/pdf"), as: :json
        expect(response).to have_http_status(:unsupported_media_type)
      end

      it "rejects an SVG declared type (415)" do
        post move_box_capture_direct_upload_path(move, box),
             params: blob_params(content_type: "image/svg+xml"), as: :json
        expect(response).to have_http_status(:unsupported_media_type)
      end

      it "blocks a sealed (non-capturable) box" do
        sealed = create(:box, move:, number: "9", status: "sealed")
        post move_box_capture_direct_upload_path(move, sealed), params: blob_params, as: :json
        expect(response).to have_http_status(:redirect)
      end
    end
  end
end
