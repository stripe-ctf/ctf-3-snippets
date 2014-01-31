class CTF3::Docker::Container
  include Chalk::Log

  attr_reader :rubysh, :metadata, :booted, :crashed

  def initialize(username, opts={})
    @username = username
    @opts = opts
    @booted = false
    @exitstatus = nil
    @metadata = opts[:metadata]
    @networking = opts.fetch(:networking, false)

    init_paths
  end

  def init_paths
    @tmpdir = CTF3::Utils.mktmpdir('docker')
    @cidfile = File.join(@tmpdir, 'cidfile')
  end

  def rubysh(*command)
    # We'll add CWF support at some point, probably
    username = @username
    command.each do |arg|
      next unless arg.kind_of?(Hash)
      raise NotImplementedError if arg[:cwd]
      if user = arg.delete(:username)
        username = user
      end
    end

    cwd = @opts[:cwd] || "/home/#{username}"
    command = [
      {env: {}},
      'lxc-attach', '-n', docker_id, '--keep-env',
      '--', '/ctf3/shell.sh', username, cwd] +
      command
    CTF3::Utils.rubysh(*command)
  end

  def boot
    start
    wait_for_boot
  end

  def terminate
    with_timeout(15) do
      kill_container
    end
  ensure
    cleanup
  end

  def get_cpu_usage
    cgroup_get('cpuacct.usage').to_i
  end

  def docker_id
    @docker_id ||= File.read(@cidfile) if File.exists?(@cidfile)
  end

  def wait_for_boot
    log.debug('wait_for_boot#start')
    raise "No rubysh: #{self.inspect}" unless @rubysh
    with_timeout(100) do
      @rubysh.read(:stdout, how: :partial)
      if zombie?
        @rubysh.wait
        @crashed = true
      else
        @booted = true
        update_hosts
      end
    end
    log.debug('wait_for_boot#end')
    @booted
  end

  def start
    # No local docker for you!
    if !CTF3.live?
      local_cwd = @opts.fetch(:local_cwd)
      return Rubysh(*@command, cwd: local_cwd).run_async
    end

    passwd = Etc.getpwnam(@username)

    cmdline = [
      'docker', 'run',
      '-i',
      '-m', '500m', # memory limit
      '-cidfile', @cidfile
      ]

    if name_base = @opts[:name_base]
      cmdline << '-name' << "#{name_base}-#{Chalk::Tools::StringUtils.random}"
    end

    if volumes = @opts[:volumes]
      volumes.each do |local, remote, mode|
        raise "Invalid local: #{local}" if local.include?(':')
        raise "Invalid remote: #{remote}" if remote.include?(':')
        cmdline << '-v' << "#{local}:#{remote}:#{mode}"
      end
    end

    tag = @opts.fetch(:tag, CTF3.docker_tag)
    timeout = @opts.fetch(timeout, 600).to_s

    networking = @networking
    cmdline << "-n=#{networking}"
    cmdline << '-lxc-conf=lxc.cgroup.cpu.shares = 512'

    # The runtime expects username, uid as the first 2 args
    cmdline << "colossus1.cluster:9001/stripectf/runtime:#{tag}"
    cmdline << '/ctf3/init.sh'
    cmdline << @username
    cmdline << passwd.uid
    cmdline << timeout
    cmdline << @opts[:level].to_s
    # Capture stdin/stdout
    cmdline << Rubysh.<
    cmdline << Rubysh.>

    @rubysh = CTF3::Utils.rubysh(*cmdline).run_async
  end

  def with_timeout(timeout, &blk)
    begin
      Timeout.timeout(timeout) do
        blk.call
      end
    rescue Timeout::Error => e
      Timeout.timeout(5) do
        if @booted
          kill_container
        else
          log.error("Timed out before even booting. Don't know which ID belongs to the container")
        end

        raise
      end
    end
  end

  private

  def zombie?
    # It'd be better to do this, but if it's dead, then rubysh will
    # run into trouble waiting on it, now won't it.
    # status = Process.waitpid2(@rubysh.pid, Process::WNOHANG)
    begin
      status = File.read("/proc/#{@rubysh.pid}/status")
    rescue Errno::ENOENT # in case we've already reaped
      log.info('Container has died and already been reaped')
      return true
    end

    state = status.split("\n")[1].split("\t")[1]
    if state.start_with?('Z')
      log.info('Container is a zombie, sorry', state: state)
      return true
    else
      return false
    end
  end

  def cleanup
    return unless @rubysh

    CTF3::Utils.finalize_rubysh(@rubysh)
    bytes = @rubysh.read
    log.info('Pending output from Rubysh', output: bytes) if bytes.length > 0

    # Clean up the container
    id = docker_id
    if id && id.length > 0 && !$hack_nocleanup
      begin
        CTF3::Utils.rubysh('docker', 'rm', id).check_call
      rescue Rubysh::Error::BadExitError => e
        log.error('Ignoring issue removing docker container -- we should maybe care though', e.to_s)
      end
    end

    log.info('Removing', tmpdir: @tmpdir, cidfile: @cidfile)
    FileUtils.rm_rf(@tmpdir)
    FileUtils.rm_f(@cidfile)
  end

  def update_hosts
    return if @networking

    base = "/var/lib/docker/containers/#{docker_id}"
    hostname = File.read(File.join(base, 'hostname'))
    File.open(File.join(base, 'hosts'), 'a') {|f| f.write("127.0.1.1 #{hostname}\n")}
    log.info('Updating /etc/hosts to contain hostname', hostname: hostname)
  end

  def cgroup_set(parameter, limit)
    group = parameter.split('.').first
    log.info('Setting cgroup param', docker_id: docker_id, parameter: parameter, limit: limit)
    File.write("/sys/fs/cgroup/#{group}/lxc/#{docker_id}/#{parameter}", "#{limit}\n")
  end

  def cgroup_get(parameter)
    group = parameter.split('.').first
    File.read("/sys/fs/cgroup/#{group}/lxc/#{docker_id}/#{parameter}").chomp
  end

  def kill_container
    return unless docker_id && docker_id.length > 0
    begin
      CTF3::Utils.rubysh('docker', 'kill', docker_id).check_call
    rescue Rubysh::Error::BadExitError => e
      log.error('Ignoring issue killing docker container -- we should maybe care though', e.to_s)
    end
  end

  def kill_init
    log.debug('kill_init#start')
    begin
      @rubysh.write('die') if @rubysh
    rescue Rubysh::Error::AlreadyRunError
      log.info('Got an Rubysh::Error::AlreadyRunError')
    end
    log.debug('kill_init#end')
  end
end
