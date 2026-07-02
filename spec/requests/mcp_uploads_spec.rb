# frozen_string_literal: true

require "rails_helper"

# #110 upload leg + #139 image validation. The client POSTs raw bytes; only a
# recognition-supported image (sniffed from magic bytes, not the filename) may be
# stored. Tenant + token auth mirror the MCP endpoint spec.
RSpec.describe "MCP uploads" do
  let(:admin) { create(:user) }
  let(:move) { create(:move, created_by: admin) }
  let(:raw_token) { MoveIntegrationToken.generate_raw_token }
  let!(:token) do
    create(:move_integration_token, move:, created_by: admin,
                                    token_digest: MoveIntegrationToken.digest(raw_token))
  end

  before do
    allow_any_instance_of(McpUploadsController) # rubocop:disable RSpec/AnyInstance
      .to receive(:current_tenant).and_return("acme")
  end

  def upload(body, bearer: raw_token)
    headers = { "Content-Type" => "application/octet-stream" }
    headers["Authorization"] = "Bearer #{bearer}" if bearer
    post "/mcp/uploads", params: body, headers: headers
  end

  def png_bytes
    Rails.root.join("spec/fixtures/files/sample_image.png").binread
  end

  it "stores a real image and returns a signed_id" do
    expect { upload(png_bytes) }.to change(ActiveStorage::Blob, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body["signed_id"]).to be_present
    expect(ActiveStorage::Blob.last.content_type).to eq("image/png")
  end

  it "rejects non-image bytes without creating a blob" do
    expect { upload("this is plainly not an image") }
      .not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:unsupported_media_type)
  end

  it "rejects an SVG without creating a blob (sniffs as image/* but is markup, #498)" do
    svg = %(<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>)
    expect { upload(svg) }.not_to change(ActiveStorage::Blob, :count)
    expect(response).to have_http_status(:unsupported_media_type)
  end

  it "rejects an empty body" do
    upload("")
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects an unauthenticated request" do
    upload(png_bytes, bearer: nil)
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a revoked token" do
    token.update!(revoked_at: Time.current)
    expect { upload(png_bytes) }.not_to change(ActiveStorage::Blob, :count)
    expect(response).to have_http_status(:unauthorized)
  end
end
