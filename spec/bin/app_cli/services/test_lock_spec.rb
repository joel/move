require "spec_helper"
require "tmpdir"
require_relative "../../../../bin/cli-files/app-cmd/test_lock"

RSpec.describe AppCLI::Services::TestLock do
  subject(:lock) { described_class.new(path: path) }

  let(:tmp) { Dir.mktmpdir("lock") }
  let(:path) { File.join(tmp, "tmp/bin-cli-app-test.lock") }

  after { FileUtils.remove_entry(tmp) }

  it "records the holder while the block runs and returns its value" do
    seen = nil
    result = lock.synchronize("/wt (branch b)") do
      seen = File.read(path)
      42
    end
    expect(result).to eq(42)
    expect(seen).to match(%r{\Apid #{Process.pid}, /wt \(branch b\), started \d{4}-})
  end

  it "refuses an overlapping run and names the holder" do
    lock.synchronize("/wt-a (branch a)") do
      expect { described_class.new(path: path).synchronize("/wt-b (branch b)") { :never } }
        .to raise_error(Thor::Error, %r{Another `bin/cli app test` is running \(pid \d+, /wt-a \(branch a\)})
    end
  end

  it "words the refusal with the busy text it was given" do
    lock.synchronize("/wt-a (branch a)") do
      other = described_class.new(path: path, busy: "Refused: another restart is in progress")
      expect { other.synchronize("/wt-b (branch b)") { :never } }
        .to raise_error(Thor::Error, %r{\ARefused: another restart is in progress \(pid \d+, /wt-a \(branch a\)})
    end
  end

  it "is refused by another process holding it" do
    lock # build the path before forking: the child must lock the same file
    reader, writer = IO.pipe
    pid = fork do
      reader.close
      lock.synchronize("child") do
        writer.puts("locked")
        sleep 5
      end
    end
    writer.close
    reader.gets
    expect { lock.synchronize("parent") { :never } }.to raise_error(Thor::Error, /child/)
  ensure
    Process.kill("TERM", pid) if pid
    Process.wait(pid) if pid
  end

  it "releases the lock even when the block raises" do
    expect { lock.synchronize("x") { raise "boom" } }.to raise_error("boom")
    expect(lock.synchronize("y") { :ran }).to eq(:ran)
    expect(File.read(path)).to be_empty
  end
end
