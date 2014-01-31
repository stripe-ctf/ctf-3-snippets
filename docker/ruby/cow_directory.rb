class CTF3::Docker::COWDirectory
  include Chalk::Log

  attr_reader :target

  def initialize(lowerdir)
    @lowerdir = lowerdir
    @upperdir = CTF3::Utils.mktmpdir('upperdir')
    @target = CTF3::Utils.mktmpdir('targetdir')

    @mounted = false
  end

  def mount
    CTF3::Utils.rubysh(
      'mount', '-t', 'overlayfs',
      '-o', "lowerdir=#{@lowerdir},upperdir=#{@upperdir}",
      'overlayfs', @target
      ).check_call

    @mounted = true
  end

  def umount(destroy=true)
    if @mounted
      CTF3::Utils.rubysh('umount', @target).check_call
    end

    if destroy
      log.info('Removing directories', upperdir: @upperdir, target: @target)
      FileUtils.rm_rf(@upperdir)
      FileUtils.rmdir(@target)
    end
  rescue => e
    log.error('Could not umount; ignoring', message: e.to_s)
  end

  def to_json
    inspect
  end
end
