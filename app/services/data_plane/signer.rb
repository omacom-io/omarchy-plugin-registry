module DataPlane
  # Detached Ed25519 signatures over every index file — clients verify the
  # index (which carries tarball checksums), so the whole chain is covered.
  # The kill list especially must be unforgeable.
  #
  # Key: REGISTRY_SIGNING_SEED (base64, 32 bytes) in production; dev/test
  # generate and persist one under storage/ so signatures stay stable locally.
  module Signer
    module_function

    def signing_key
      @signing_key ||= Ed25519::SigningKey.new(seed)
    end

    def public_key_base64
      Base64.strict_encode64(signing_key.verify_key.to_bytes)
    end

    def sign_base64(content)
      Base64.strict_encode64(signing_key.sign(content))
    end

    def verify?(content, signature_base64)
      signing_key.verify_key.verify(Base64.strict_decode64(signature_base64), content)
    rescue Ed25519::VerifyError, ArgumentError
      false
    end

    # Verification that stays fail-closed THROUGH a key rotation: the current
    # key, or — when the operator supplied it — the explicitly named previous
    # public key. Never an unverified bypass.
    def verify_any?(content, signature_base64)
      return true if verify?(content, signature_base64)
      key = previous_verify_key
      return false unless key
      key.verify(Base64.strict_decode64(signature_base64), content)
    rescue Ed25519::VerifyError, ArgumentError
      false
    end

    def previous_verify_key
      encoded = ENV["REGISTRY_PREVIOUS_SIGNING_PUBKEY"]
      return nil if encoded.blank?
      Ed25519::VerifyKey.new(Base64.strict_decode64(encoded))
    end

    def seed
      if (env_seed = ENV["REGISTRY_SIGNING_SEED"]).present?
        Base64.strict_decode64(env_seed)
      elsif Rails.env.production?
        raise "REGISTRY_SIGNING_SEED is required in production"
      else
        local_seed(Rails.root.join("storage", "#{Rails.env}_signing.seed"))
      end
    end

    LOCAL_SEED_BYTES = 32
    PRIVATE_FILE_MODE = 0o600

    # Rails tests run in parallel processes. Serialize first-use creation on a
    # separate lock file and promote a complete seed atomically so no reader
    # can observe the zero-byte window created by Pathname#binwrite.
    def local_seed(seed_path)
      seed_path = Pathname.new(seed_path)
      FileUtils.mkdir_p(seed_path.dirname, mode: 0o700)
      validate_local_seed_directory!(seed_path.dirname)
      lock_path = Pathname.new("#{seed_path}.lock")
      ensure_local_lock_file!(lock_path)
      sync_directory!(seed_path.dirname)
      lock_flags = File::RDWR
      lock_flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)

      File.open(lock_path, lock_flags) do |lock|
        secure_open_file!(lock_path, lock, "lock", secret: false)
        raise "could not lock local registry signing seed" unless lock.flock(File::LOCK_EX)

        reject_non_regular_path!(seed_path, "seed")
        write_local_seed(seed_path) unless seed_path.exist?
        sync_directory!(seed_path.dirname)
        read_local_seed(seed_path)
      end
    end

    def ensure_local_lock_file!(lock_path)
      reject_non_regular_path!(lock_path, "lock")
      flags = File::WRONLY | File::CREAT | File::EXCL
      flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)

      begin
        File.open(lock_path, flags, PRIVATE_FILE_MODE) do |file|
          file.chmod(PRIVATE_FILE_MODE)
          file.fsync
        end
      rescue Errno::EEXIST
        nil
      end

      stat = lock_path.lstat
      unless stat.file? && stat.uid == Process.euid
        raise "local registry signing lock must be a regular file owned by the current user"
      end
      File.chmod(PRIVATE_FILE_MODE, lock_path) unless (stat.mode & 0o777) == PRIVATE_FILE_MODE
    end

    def read_local_seed(seed_path)
      flags = File::RDONLY
      flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)

      File.open(seed_path, flags) do |file|
        secure_open_file!(seed_path, file, "seed", secret: true)
        expected = LOCAL_SEED_BYTES
        declared_size = file.stat.size
        unless declared_size == expected
          raise "invalid local registry signing seed: expected #{expected} bytes, got #{declared_size}"
        end

        bytes = file.read(expected + 1).to_s
        unless bytes.bytesize == expected && file.read(1).nil?
          raise "invalid local registry signing seed: expected #{expected} bytes, got #{bytes.bytesize}"
        end
        bytes
      end
    end

    def write_local_seed(seed_path)
      temporary_path = Pathname.new("#{seed_path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}")
      File.open(temporary_path, File::WRONLY | File::CREAT | File::EXCL, PRIVATE_FILE_MODE) do |file|
        file.binmode
        bytes = Ed25519::SigningKey.generate.seed
        written = file.write(bytes)
        raise "could not write complete local registry signing seed" unless written == LOCAL_SEED_BYTES
        file.flush
        file.chmod(PRIVATE_FILE_MODE)
        unless (file.stat.mode & 0o777) == PRIVATE_FILE_MODE
          raise "could not secure local registry signing seed permissions"
        end
        file.fsync
      end
      File.rename(temporary_path, seed_path)
    ensure
      FileUtils.rm_f(temporary_path) if temporary_path
    end

    def validate_local_seed_directory!(directory)
      stat = directory.lstat
      mode = stat.mode & 0o777
      unless stat.directory? && stat.uid == Process.euid && (mode & 0o022).zero?
        raise "local registry signing seed directory must be owned by the current user and not group/world writable"
      end
    end

    def reject_non_regular_path!(path, label)
      stat = path.lstat
      raise "local registry signing #{label} must be a regular file" unless stat.file?
    rescue Errno::ENOENT
      nil
    end

    def secure_open_file!(path, file, label, secret:)
      path_stat = path.lstat
      file_stat = file.stat
      same_file = path_stat.dev == file_stat.dev && path_stat.ino == file_stat.ino
      unless path_stat.file? && file_stat.file? && same_file && file_stat.uid == Process.euid
        raise "local registry signing #{label} must be a regular file owned by the current user"
      end

      mode = file_stat.mode & 0o777
      if secret
        unless (mode & 0o077).zero?
          raise "local registry signing seed permissions must not allow group or world access"
        end
      elsif mode != PRIVATE_FILE_MODE
        file.chmod(PRIVATE_FILE_MODE)
      end
    end

    def sync_directory!(directory)
      File.open(directory, File::RDONLY) do |file|
        raise "local registry signing seed parent must be a directory" unless file.stat.directory?
        file.fsync
      end
    end

    private_class_method :local_seed, :ensure_local_lock_file!, :read_local_seed, :write_local_seed,
      :validate_local_seed_directory!, :reject_non_regular_path!, :secure_open_file!, :sync_directory!

    def reset! = @signing_key = nil
  end
end
