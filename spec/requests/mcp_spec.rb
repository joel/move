# frozen_string_literal: true

require "rails_helper"

# D13 — MCP assistant endpoint. Exercises auth (valid / revoked / absent /
# cross-Move), the tool surface, and the audit trail through the real JSON-RPC
# POST path. Apartment::Tenant.current is stubbed to a non-public slug so the
# endpoint resolves as if on an org subdomain (records live in the public test
# schema, so the stub is enough — mirrors the other tenant request specs).
RSpec.describe "MCP endpoint" do
  let(:admin) { create(:user) }
  let(:move) { create(:move, created_by: admin) }
  let(:raw_token) { MoveIntegrationToken.generate_raw_token }
  let!(:token) do
    create(:move_integration_token, move:, created_by: admin,
                                    token_digest: MoveIntegrationToken.digest(raw_token))
  end

  # The endpoint only serves an org subdomain; stub the controller's tenant
  # resolution rather than Apartment globally (the elevator middleware also reads
  # Apartment::Tenant.current, and stubbing it there destabilises the connection
  # across examples). Token rows live in the public test schema, which is enough.
  # McpController is ActionController::API, so the shared stub_current_* helpers
  # (which target ApplicationController) don't reach it — stub the instance.
  before do
    # current_tenant lives in McpAuthentication, shared by both MCP controllers.
    [McpController, McpUploadsController].each do |controller|
      allow_any_instance_of(controller).to receive(:current_tenant).and_return("acme") # rubocop:disable RSpec/AnyInstance
    end
  end

  # NB: do not name params `method`/`id` — they shadow methods the integration
  # `post` helper relies on (via Runner#method_missing), silently skipping dispatch.
  def rpc(rpc_method, rpc_params = {}, bearer: raw_token, req_id: 1)
    # The Streamable HTTP transport (JSON mode) requires Accept: application/json.
    headers = { "Content-Type" => "application/json", "Accept" => "application/json" }
    headers["Authorization"] = "Bearer #{bearer}" if bearer
    body = { jsonrpc: "2.0", id: req_id, method: rpc_method, params: rpc_params }.to_json
    post "/mcp", params: body, headers: headers
    response.parsed_body
  end

  def tool_call(name, arguments = {})
    rpc("tools/call", { name:, arguments: })
  end

  # The structuredContent of a successful tools/call result.
  def structured(body)
    body.dig("result", "structuredContent")
  end

  describe "authentication" do
    it "rejects an absent token with 401" do
      rpc("tools/list", bearer: nil)
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an unknown token with 401" do
      rpc("tools/list", bearer: "mcp_nope")
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a revoked token with 401" do
      token.update!(revoked_at: Time.current)
      rpc("tools/list")
      expect(response).to have_http_status(:unauthorized)
    end

    it "404s when there is no tenant (apex)" do
      allow_any_instance_of(McpController).to receive(:current_tenant).and_return(nil) # rubocop:disable RSpec/AnyInstance
      rpc("tools/list")
      expect(response).to have_http_status(:not_found)
    end

    it "touches last_used_at on a valid call" do
      expect { tool_call("list_boxes") }.to(change { token.reload.last_used_at })
    end
  end

  describe "HTTP transport semantics" do
    it "returns 400 for malformed JSON (not a 200 JSON-RPC body)" do
      post "/mcp", params: "{not json",
                   headers: { "Content-Type" => "application/json", "Accept" => "application/json",
                              "Authorization" => "Bearer #{raw_token}" }
      expect(response).to have_http_status(:bad_request)
    end

    it "rejects a non-JSON Content-Type with 415" do
      post "/mcp", params: "hi",
                   headers: { "Content-Type" => "text/plain", "Accept" => "application/json",
                              "Authorization" => "Bearer #{raw_token}" }
      expect(response).to have_http_status(:unsupported_media_type)
    end
  end

  describe "tools/list" do
    it "advertises the available tools" do
      body = rpc("tools/list")
      names = body.dig("result", "tools").pluck("name")
      expect(names).to contain_exactly(
        "list_boxes", "get_box_contents", "search_items", "add_item_to_box",
        "create_media_upload", "add_media_to_box", "move_item", "mark_unpacked", "get_volume_summary"
      )
    end
  end

  describe "list_boxes" do
    it "returns only the token's Move's boxes (cross-Move isolation)" do
      mine = create(:box, move:, number: 1)
      other_move = create(:move)
      create(:box, move: other_move, number: 99)

      numbers = structured(tool_call("list_boxes"))["boxes"].pluck("number")

      expect(numbers).to eq([mine.number.to_i])
    end
  end

  describe "get_box_contents" do
    it "lists the in-box items of a box" do
      box = create(:box, move:, number: 2)
      create(:item, move:, box:, name: "Lamp")

      data = structured(tool_call("get_box_contents", { box_number: 2 }))

      expect(data["items"].pluck("name")).to include("Lamp")
    end

    it "errors for a box in another Move" do
      other = create(:move)
      create(:box, move: other, number: 7)

      body = tool_call("get_box_contents", { box_number: 7 })

      expect(body.dig("result", "isError")).to be(true)
    end
  end

  describe "add_item_to_box" do
    it "creates an item through the shared action and audits with source mcp" do
      box = create(:box, move:, number: 3)
      allow(Rails.event).to receive(:notify).and_call_original

      expect { tool_call("add_item_to_box", { box_number: 3, name: "Kettle", quantity: 2 }) }
        .to change { box.items.count }.by(1)

      item = box.items.order(:created_at).last
      expect(item.name).to eq("Kettle")
      expect(Rails.event).to have_received(:notify).with(
        "mcp.tool_called",
        hash_including(source: :mcp, tool: "add_item_to_box", move_id: move.id, item_id: item.id)
      )
    end
  end

  describe "move_item" do
    it "moves an item to another box in the same Move" do
      from = create(:box, move:, number: 4)
      to = create(:box, move:, number: 5)
      item = create(:item, move:, box: from, name: "Mug")

      tool_call("move_item", { item_id: item.id, to_box_number: 5 })

      expect(item.reload.box_id).to eq(to.id)
    end
  end

  describe "mark_unpacked" do
    it "marks an item removed from its box (unpacking)" do
      box = create(:box, move:, number: 6, status: "unpacking")
      item = create(:item, move:, box:, name: "Plate")

      tool_call("mark_unpacked", { item_id: item.id })

      expect(item.reload.presence_state).to eq("removed")
    end

    it "refuses to mark_unpacked while the box is still packing" do
      box = create(:box, move:, number: 7, status: "packing")
      item = create(:item, move:, box:, name: "Plate")

      body = tool_call("mark_unpacked", { item_id: item.id })

      expect(body.dig("result", "isError")).to be(true)
      expect(item.reload.presence_state).to eq("in_box")
    end
  end

  describe "mutations on an archived (read-only) move" do
    before { move.update!(status: "archived") }

    it "blocks add_item_to_box without creating a record" do
      box = create(:box, move:, number: 10)

      body = nil
      expect { body = tool_call("add_item_to_box", { box_number: 10, name: "Nope" }) }
        .not_to change(box.items, :count)
      expect(body.dig("result", "isError")).to be(true)
    end

    it "blocks move_item" do
      from = create(:box, move:, number: 11)
      create(:box, move:, number: 12)
      item = create(:item, move:, box: from, name: "Frozen")

      tool_call("move_item", { item_id: item.id, to_box_number: 12 })

      expect(item.reload.box_id).to eq(from.id)
    end

    it "blocks mark_unpacked" do
      box = create(:box, move:, number: 13)
      item = create(:item, move:, box:, name: "Still here")

      tool_call("mark_unpacked", { item_id: item.id })

      expect(item.reload.presence_state).to eq("in_box")
    end

    it "still allows read tools" do
      create(:box, move:, number: 14)
      expect(structured(tool_call("list_boxes"))["boxes"].length).to eq(1)
    end
  end

  describe "direct upload: create_media_upload + add_media_to_box" do
    def png_bytes = Rails.root.join("spec/fixtures/files/sample_image.png").binread

    def auth_headers(extra = {})
      { "Authorization" => "Bearer #{raw_token}", "Content-Type" => "application/octet-stream" }.merge(extra)
    end

    # Full round-trip through the real endpoints: create_media_upload returns the
    # app upload URL; POST the raw bytes there (McpUploadsController streams them
    # into a blob and returns a Move-scoped signed_id) to hand to add_media_to_box.
    def upload(bytes, filename: "a.png")
      url = structured(tool_call("create_media_upload", {}))["url"]
      post "#{url}?filename=#{filename}", params: bytes, headers: auth_headers
      expect(response).to have_http_status(:created)
      response.parsed_body["signed_id"]
    end

    describe "create_media_upload" do
      it "returns the app upload URL and advertises the auth/method/body contract" do
        data = structured(tool_call("create_media_upload", {}))

        expect(data["url"]).to end_with("/mcp/uploads")
        expect(data["method"]).to eq("POST")
        # Only literally-usable headers (no placeholder auth a client might send verbatim).
        expect(data["headers"]).to eq("Content-Type" => "application/octet-stream")
        expect(data["instructions"]).to include("Authorization: Bearer")
      end

      it "rejects an oversized declared size up front" do
        body = tool_call("create_media_upload", { byte_size: Media::MAX_IMAGE_BYTES + 1 })
        expect(body.to_json).to match(/too large/i)
      end
    end

    describe "POST /mcp/uploads (streaming upload)" do
      it "streams the bytes into a blob and returns a Move-scoped signed_id" do
        post "/mcp/uploads", params: png_bytes, headers: auth_headers

        expect(response).to have_http_status(:created)
        signed = response.parsed_body["signed_id"]
        # The signed_id verifies under this Move's purpose, not another's.
        expect(ActiveStorage::Blob.find_signed(signed, purpose: Captures::Create.signed_id_purpose(move))).to be_present
        expect(ActiveStorage::Blob.find_signed(signed, purpose: Captures::Create.signed_id_purpose(create(:move)))).to be_nil
      end

      it "rejects an over-cap body before storing it (independent of Content-Length)" do
        stub_const("Media::MAX_IMAGE_BYTES", 10)

        expect do
          post "/mcp/uploads", params: "x" * 50, headers: auth_headers
        end.not_to change(ActiveStorage::Blob, :count)
        expect(response).to have_http_status(:content_too_large)
      end

      it "401s without a token" do
        post "/mcp/uploads", params: png_bytes, headers: { "Content-Type" => "application/octet-stream" }
        expect(response).to have_http_status(:unauthorized)
      end

      it "403s when the Move is archived (can't bypass create_media_upload's guard)" do
        move.update!(status: "archived")

        expect do
          post "/mcp/uploads", params: png_bytes, headers: auth_headers
        end.not_to change(ActiveStorage::Blob, :count)
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe "add_media_to_box (attach by signed_id)" do
      let!(:box) { create(:box, move:, number: 9, status: "packing") }

      it "attaches an uploaded blob and queues recognition (captured_via mcp)" do
        tool_call("add_media_to_box", { box_number: 9, signed_id: upload(png_bytes) })

        media = box.media.order(:created_at).last
        expect(media).to be_present
        expect(media.captured_via).to eq("mcp")
        expect(media.image.content_type).to eq("image/png")
      end

      it "transcodes a non-native uploaded blob (TIFF) to JPEG on attach" do
        tiff = Rails.root.join("spec/fixtures/files/sample.tiff").binread
        signed = upload(tiff, filename: "a.tiff")

        tool_call("add_media_to_box", { box_number: 9, signed_id: signed })

        expect(box.media.last.image.content_type).to eq("image/jpeg")
      end

      it "rejects non-image bytes at upload by sniffing them (not the declared name)" do
        # Even with an image-y filename, the byte sniff rejects non-image content
        # at the upload step (#139), so no orphaned blob is stored and it never
        # reaches add_media_to_box.
        url = structured(tool_call("create_media_upload", {}))["url"]

        expect do
          post "#{url}?filename=a.png", params: "this is not an image", headers: auth_headers
        end.not_to change(ActiveStorage::Blob, :count)
        expect(response).to have_http_status(:unsupported_media_type)
        expect(box.media.count).to eq(0)
      end

      it "rejects an unknown/invalid signed_id" do
        body = tool_call("add_media_to_box", { box_number: 9, signed_id: "bogus" })

        expect(box.media.count).to eq(0)
        expect(body.to_json).to match(/could not be found|Action failed/i)
      end

      it "rejects a blob signed for a different Move (cross-Move binding)" do
        other_move = create(:move)
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(png_bytes), filename: "a.png", content_type: "image/png"
        )
        # A valid signed_id, but bound to another Move's purpose — must not attach here.
        signed = blob.signed_id(purpose: Captures::Create.signed_id_purpose(other_move))

        body = tool_call("add_media_to_box", { box_number: 9, signed_id: signed })

        expect(box.media.count).to eq(0)
        expect(body.to_json).to match(/could not be found|Action failed/i)
      end
    end
  end

  describe "get_volume_summary" do
    it "returns the Move's box count" do
      create(:box, move:, number: 8)

      data = structured(tool_call("get_volume_summary"))

      expect(data["box_count"]).to eq(1)
    end
  end
end
