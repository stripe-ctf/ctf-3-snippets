module CTF3::Submission::RPC
  require 'ctf3/submission/rpc/raw'
  require 'ctf3/submission/rpc/structured'
  require 'ctf3/submission/rpc/cloneable'
  require 'ctf3/submission/rpc/repliable'

  require 'ctf3/submission/rpc/build_rpc'
  require 'ctf3/submission/rpc/final_score_rpc'
  require 'ctf3/submission/rpc/result_rpc'
  require 'ctf3/submission/rpc/score_rpc'

  require 'ctf3/submission/rpc/level0_result_rpc'
  require 'ctf3/submission/rpc/level2_result_rpc'
  require 'ctf3/submission/rpc/level3_result_rpc'
  require 'ctf3/submission/rpc/level4_result_rpc'

  # Combine with Rubysh's :on_read option to react to an output stream
  # up to a truncation limit.
  #
  # For example:
  #
  #     passthrough = output_collector {|data| print data}
  #     on_read = Proc.new {|target, data| passthrough.call(data)}
  #     Rubysh.run('command', on_read: on_read, Rubysh.>)
  #
  # would result in printing the first 400KB of stdout.
  #
  # You may want to combine multiple output collectors as in
  #
  #     stdout = output_collector {|data| print data}
  #     stderr = output_collector {|data| print data}
  #     on_read = Proc.new do |target, data|
  #       case target
  #       when :stdout then stdout.call(data)
  #       when :stderr then stderr.call(data)
  #     end
  #     Rubysh.run('command', on_read: on_read,
  #       Rubysh.stdout > :stdout, Rubysh.stderr > :stderr)
  #
  # which would result in both stdout and stderr being printed up to
  # independent truncation limits.
  def self.output_collector(limit=nil, &blk)
    limit ||= 400 * 1024
    byte_counter = 0
    done = false

    Proc.new do |target_name, bytes|
      next if done || bytes == Rubysh::Subprocess::ParallelIO::EOF

      if limit
        remaining_limit = limit - byte_counter
        if bytes.bytesize > remaining_limit
          bytes = bytes[0...remaining_limit] + "... (truncated at #{limit / 1024}KB)\n"
          done = true
        end
        byte_counter += bytes.bytesize
      end

      blk.call(bytes)
    end
  end
end
