class CTF3::Docker::Manager
  include Chalk::Log

  def initialize
    @initial = []
    @attempted = []
    @booted = []
  end

  def attempt(*args)
    container = CTF3::Docker::Container.new(*args)
    container.start
    @attempted << container
    container
  end

  # Spin these up here so that you get backtraces immediately
  def register(*args)
    worker = attempt(*args)
    @initial << [args, worker]
  end

  def boot
    booted = []

    @initial.each do |args, worker|
      while !worker.booted
        worker.wait_for_boot
        if worker.crashed
          log.info('It appears that our worker has crashed; trying again')

          worker.terminate
          worker = attempt(*args)
        end
      end
      booted << worker
    end

    booted
  end

  # TODO: terminating a container takes almost a second right now,
  # since you have to docker kill it and then docker rm it. I suspect
  # we can be a lot smarter about this.
  def terminate
    log.info('Terminating containers', containers: @attempted.length)
    begin
      ts = @attempted.map do |attempted|
        Thread.new {attempted.terminate}
      end
      ts.each(&:join)
    rescue Exception => e
      log.error('Could not terminate all containers', containers: @attempted)
      raise
    end
  end
end
