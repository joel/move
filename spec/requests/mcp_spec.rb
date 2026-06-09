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
    allow_any_instance_of(McpController).to receive(:current_tenant).and_return("acme") # rubocop:disable RSpec/AnyInstance
  end

  # NB: do not name params `method`/`id` — they shadow methods the integration
  # `post` helper relies on (via Runner#method_missing), silently skipping dispatch.
  def rpc(rpc_method, rpc_params = {}, bearer: raw_token, req_id: 1)
    headers = { "Content-Type" => "application/json" }
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

  describe "tools/list" do
    it "advertises the eight initial tools" do
      body = rpc("tools/list")
      names = body.dig("result", "tools").pluck("name")
      expect(names).to contain_exactly(
        "list_boxes", "get_box_contents", "search_items", "add_item_to_box",
        "add_media_to_box", "move_item", "mark_unpacked", "get_volume_summary"
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
    it "marks an item removed from its box" do
      box = create(:box, move:, number: 6)
      item = create(:item, move:, box:, name: "Plate")

      tool_call("mark_unpacked", { item_id: item.id })

      expect(item.reload.presence_state).to eq("removed")
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

  describe "get_volume_summary" do
    it "returns the Move's box count" do
      create(:box, move:, number: 8)

      data = structured(tool_call("get_volume_summary"))

      expect(data["box_count"]).to eq(1)
    end
  end
end
