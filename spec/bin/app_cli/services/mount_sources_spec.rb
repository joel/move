require "spec_helper"
require "tmpdir"
require_relative "../../../../bin/cli-files/app-cmd/mount_sources"

RSpec.describe AppCLI::Services::MountSources do
  subject(:sources) { described_class.new(checkout_path: worktree, main_path: main) }

  let(:tmp) { Dir.mktmpdir("mounts") }
  let(:main) { File.join(tmp, "main") }
  let(:worktree) { File.join(tmp, "wt") }

  before { FileUtils.mkdir_p([File.join(main, "config"), File.join(worktree, "config")]) }
  after { FileUtils.remove_entry(tmp) }

  def entries(root) = Dir.glob("**/*", File::FNM_DOTMATCH, base: root).reject { |e| e.end_with?(".") }.sort

  it "falls back to the main checkout's master.key and .env file" do
    File.write(File.join(main, "config/master.key"), "k")
    File.write(File.join(main, ".env.development"), "A=1")

    expect(sources.master_key_path).to eq(File.join(main, "config/master.key"))
    expect(sources.env_file_path("development")).to eq(File.join(main, ".env.development"))
    expect(entries(worktree)).to eq(["config"])
  end

  it "prefers the worktree's own files" do
    File.write(File.join(main, "config/master.key"), "k")
    File.write(File.join(worktree, "config/master.key"), "own")
    File.write(File.join(worktree, ".env.test"), "B=2")

    expect(sources.master_key_path).to eq(File.join(worktree, "config/master.key"))
    expect(sources.env_file_path("test")).to eq(File.join(worktree, ".env.test"))
  end

  it "returns nil for an env file no checkout has" do
    expect(sources.env_file_path("test")).to be_nil
  end

  it "fails when no checkout has a master.key" do
    expect { sources.master_key_path }.to raise_error(Thor::Error, %r{Missing config/master.key in #{worktree} and #{main}})
  end

  it "refuses an empty master.key" do
    File.write(File.join(main, "config/master.key"), "")
    expect { sources.master_key_path }.to raise_error(Thor::Error, %r{main/config/master.key is empty})
  end

  it "refuses a master.key it can't read" do
    key = File.join(main, "config/master.key")
    File.write(key, "k")
    allow(File).to receive(:readable?).and_call_original
    allow(File).to receive(:readable?).with(key).and_return(false)
    expect { sources.master_key_path }.to raise_error(Thor::Error, /master.key is not readable/)
  end

  it "refuses an env file it can't read" do
    env_file = File.join(main, ".env.development")
    File.write(env_file, "A=1")
    allow(File).to receive(:readable?).and_call_original
    allow(File).to receive(:readable?).with(env_file).and_return(false)
    expect { sources.env_file_path("development") }.to raise_error(Thor::Error, /.env.development is not readable/)
  end

  it "refuses a directory where the master.key file belongs, with a fix hint" do
    File.write(File.join(main, "config/master.key"), "k")
    FileUtils.mkdir_p(File.join(worktree, "config/master.key"))
    expect { sources.master_key_path }.to raise_error(Thor::Error, %r{is a directory.*rmdir .*wt/config/master.key})
  end

  it "refuses a directory where an env file belongs" do
    FileUtils.mkdir_p(File.join(main, ".env.development"))
    expect { sources.env_file_path("development") }.to raise_error(Thor::Error, /rmdir/)
  end

  it "pre-creates the container's writable dirs and writes nothing else" do
    sources.prepare!
    expect(entries(worktree)).to eq(%w[config log tmp])
  end

  it "refuses a file where a writable dir belongs" do
    File.write(File.join(worktree, "tmp"), "")
    expect { sources.prepare! }.to raise_error(Thor::Error, /tmp is a file/)
  end
end
