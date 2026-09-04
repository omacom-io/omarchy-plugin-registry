require "test_helper"
require "timeout"
require "tmpdir"

class IndexSigningTest < ActionDispatch::IntegrationTest
  setup do
    @dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @dev, role: :owner, founding: true)
    perform_enqueued_jobs do
      Registry::PublishVersion.new(user: @dev, publisher: @publisher, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build).call
    end
  end

  test "every index file carries a verifiable detached signature" do
    %w[config.json all.json revocations.json legacy-map.json index/acme/weather.json].each do |file|
      content = DataPlane.read(file)
      signature = DataPlane.read("#{file}.sig")
      assert DataPlane::Signer.verify?(content, signature), "bad signature for #{file}"
    end
  end

  test "signatures and public key are served over HTTP" do
    get "/signing-key.pub"
    assert_response :success
    key = response.body

    get "/revocations.json"
    content = response.body
    get "/revocations.json.sig"
    signature = response.body

    verify_key = Ed25519::VerifyKey.new(Base64.strict_decode64(key))
    assert verify_key.verify(Base64.strict_decode64(signature), content)
  end

  test "every fixed URL config.json advertises is actually served" do
    # A client reads config.json and follows these; an advertised endpoint
    # that 404s is a broken install path, not a cosmetic gap. The templated
    # dl/index entries are covered by the tarball and index tests.
    config = JSON.parse(DataPlane.read("config.json"))
    %w[revocations legacy_map signing_key].each do |key|
      path = URI.parse(config.fetch(key)).path
      get path
      assert_response :success, "config.json advertises #{key} at #{path}, which does not serve"
    end
  end

  test "a tampered index fails verification" do
    content = DataPlane.read("all.json")
    signature = DataPlane.read("all.json.sig")
    assert_not DataPlane::Signer.verify?(content + " ", signature)
  end

  test "signed files carry strictly increasing millisecond-anchored generations with expiry" do
    first = JSON.parse(DataPlane.read("revocations.json"))
    assert_kind_of Integer, first["generation"]
    assert_operator first["generation"], :>=, (Time.current.to_f * 1000).to_i - 60_000
    assert Time.parse(first["expires_at"]).future?

    DataPlane::Regenerate.all
    second = JSON.parse(DataPlane.read("revocations.json"))
    assert_operator second["generation"], :>, first["generation"]

    # every signed file of one run carries the same generation; the index meta
    # line carries it too
    config = JSON.parse(DataPlane.read("config.json"))
    all = JSON.parse(DataPlane.read("all.json"))
    meta = JSON.parse(DataPlane.read("index/acme/weather.json").lines.first)
    assert meta["meta"]
    assert_equal second["generation"], config["generation"]
    assert_equal second["generation"], all["generation"]
    assert_equal second["generation"], meta["generation"]
    assert Time.parse(meta["expires_at"]).future?
  end

  test "local signing seed creation is atomic across processes" do
    skip "fork is required for this race regression" unless Process.respond_to?(:fork)

    Dir.mktmpdir("registry-signing-seed") do |directory|
      seed_path = Pathname.new(directory).join("test.seed")
      gate_reader, gate_writer = IO.pipe
      ready_reader, ready_writer = IO.pipe
      workers = 16
      pids = []
      ready_tokens = nil
      statuses = nil

      begin
        Timeout.timeout(15) do
          workers.times do |index|
            pids << fork do
              File.umask(0o777)
              gate_writer.close
              ready_reader.close
              ready_writer.write(".")
              ready_writer.close
              gate_reader.read(1)
              bytes = DataPlane::Signer.send(:local_seed, seed_path)
              result_path = Pathname.new(directory).join("result-#{index}")
              File.binwrite(result_path, bytes)
              result_path.chmod(0o600)
              exit! 0
            rescue StandardError => error
              error_path = Pathname.new(directory).join("error-#{index}")
              File.write(error_path, "#{error.class}: #{error.message}")
              error_path.chmod(0o600)
              exit! 1
            end
          end
          gate_reader.close
          ready_writer.close
          ready_tokens = ready_reader.read(workers)
          ready_reader.close
          gate_writer.write("." * workers)
          gate_writer.close
          statuses = pids.map { |pid| Process.wait2(pid).last }
        end
      ensure
        [ gate_reader, gate_writer, ready_reader, ready_writer ].each do |pipe|
          pipe.close unless pipe.closed?
        end
        pids.each do |pid|
          Process.kill("KILL", pid)
        rescue Errno::ESRCH
          nil
        end
        pids.each do |pid|
          Process.wait(pid)
        rescue Errno::ECHILD
          nil
        end
      end

      errors = Dir[Pathname.new(directory).join("error-*")].map { |path| File.read(path) }
      assert_equal workers, ready_tokens.bytesize
      assert statuses.all?(&:success?), errors.join("\n")

      seeds = workers.times.map { |index| File.binread(Pathname.new(directory).join("result-#{index}")) }
      assert_equal [ 32 ], seeds.map(&:bytesize).uniq
      assert_equal 1, seeds.uniq.size
      assert_equal 0o600, seed_path.stat.mode & 0o777
    end
  end

  test "invalid local signing seed lengths fail closed without replacement" do
    Dir.mktmpdir("registry-signing-seed") do |directory|
      seed_path = Pathname.new(directory).join("test.seed")

      [ 31, 33 ].each do |size|
        original = "x" * size
        seed_path.binwrite(original)
        seed_path.chmod(0o600)
        error = assert_raises(RuntimeError) { DataPlane::Signer.send(:local_seed, seed_path) }

        assert_match(/expected 32 bytes, got #{size}/, error.message)
        assert_equal original, seed_path.binread
      end
    end
  end

  test "local signing seed rejects symlinks and non-regular files" do
    skip "FIFO support is required for this file-type regression" unless File.respond_to?(:mkfifo)

    Dir.mktmpdir("registry-signing-seed") do |directory|
      root = Pathname.new(directory)
      seed_path = root.join("test.seed")
      target_path = root.join("target.seed")
      target_path.binwrite("x" * 32)
      File.symlink(target_path, seed_path)

      error = assert_raises(RuntimeError) { DataPlane::Signer.send(:local_seed, seed_path) }
      assert_match(/seed must be a regular file/, error.message)

      seed_path.delete
      File.mkfifo(seed_path)
      error = assert_raises(RuntimeError) { DataPlane::Signer.send(:local_seed, seed_path) }
      assert_match(/seed must be a regular file/, error.message)
    end
  end

  test "local signing seed rejects previously exposed file permissions" do
    Dir.mktmpdir("registry-signing-seed") do |directory|
      seed_path = Pathname.new(directory).join("test.seed")
      expected = "x" * 32
      seed_path.binwrite(expected)
      seed_path.chmod(0o644)

      error = assert_raises(RuntimeError) { DataPlane::Signer.send(:local_seed, seed_path) }

      assert_match(/must not allow group or world access/, error.message)
      assert_equal expected, seed_path.binread
      assert_equal 0o644, seed_path.stat.mode & 0o777
    end
  end

  test "local signing seed creation recovers a current-user lock with restrictive permissions" do
    Dir.mktmpdir("registry-signing-seed") do |directory|
      root = Pathname.new(directory)
      seed_path = root.join("test.seed")
      lock_path = root.join("test.seed.lock")
      lock_path.binwrite("")
      lock_path.chmod(0o000)

      assert_equal 32, DataPlane::Signer.send(:local_seed, seed_path).bytesize
      assert_equal 0o600, lock_path.stat.mode & 0o777
      assert_equal 0o600, seed_path.stat.mode & 0o777
    end
  end

  test "local signing lock rejects symlinks" do
    Dir.mktmpdir("registry-signing-seed") do |directory|
      root = Pathname.new(directory)
      target_path = root.join("target.lock")
      target_path.binwrite("")
      File.symlink(target_path, root.join("test.seed.lock"))

      error = assert_raises(RuntimeError) { DataPlane::Signer.send(:local_seed, root.join("test.seed")) }
      assert_match(/lock must be a regular file/, error.message)
    end
  end

  test "a changed signing key refuses to replace the trust root" do
    original_pub = DataPlane.root.join("signing-key.pub").read
    DataPlane.root.join("signing-key.pub").write("SOMEONE-ELSES-KEY")
    error = assert_raises(RuntimeError) { DataPlane::Regenerate.all }
    assert_match(/refusing to replace the trust root/, error.message)
  ensure
    DataPlane.root.join("signing-key.pub").write(original_pub)
  end
end
