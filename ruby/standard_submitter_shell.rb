class CTF3::Level::StandardSubmitterShell
  include CTF3::Submission::SubmitterShell::Helpers

  def run(username, authorized_level, git_cmd, level_path)
    klass = CTF3::Level.level_klass_for(authorized_level)
    level_path = level_path[1..-1] if level_path.start_with?('/')
    unless klass.hook_authorized_path?(level_path)
      $stderr.puts("fatal: '#{level_path}' does not appear to be a git repository (are you SSHing in as the right user? You have a different user per level)")
      return 128
    end

    status = execute_in_level_repo(git_cmd, username, authorized_level)
    status
  end

  def execute_in_level_repo(git_cmd, username, authorized_level)
    storage_path = CTF3::Submission::SubmitterShell::Code.storage_path(username, authorized_level)
    CTF3::Submission::SubmitterShell::Code.setup_standard_repo!(storage_path, authorized_level) unless Dir.exists?(storage_path)

    case git_cmd
    when 'git-receive-pack'
      logged_rubysh_run('git', 'branch', '-M', 'master', 'ctf3-tmp-master', cwd: storage_path)
      base_commit = File.read(File.join(storage_path, 'base-commit')).chomp
      logged_rubysh_run('git', 'branch', '-f', 'master', base_commit, cwd: storage_path)
    when 'git-upload-pack'
      $stderr.puts
      $stderr.puts "Welcome to CTF3, Level #{authorized_level}! Happy solving."
      $stderr.puts
      $stderr.puts "- To get started, check out the (aptly-named) README.md."
      $stderr.puts "- Commit your code, and run `git push` to submit your solution for scoring."
      $stderr.puts "- You can also test run your solution locally using `test/harness`"
      $stderr.puts
    end

    runner = Rubysh.run('git-shell', '-c', "#{git_cmd} '#{storage_path}'")
    status = runner.exitstatus

    case git_cmd
    when 'git-receive-pack'
      runner, _, _ = logged_rubysh_run('git', 'branch', '-m', 'ctf3-tmp-master', 'master', cwd: storage_path)
      # Someone pushed to master in the meanwhile
      if runner.exitstatus != 0
        # Set master as the default branch
        logged_rubysh_run('git', 'symbolic-ref', 'HEAD', 'refs/heads/master', cwd: storage_path)
        # Forcibly get rid of the temporary branch
        logged_rubysh_run('git', 'branch', '-D', 'ctf3-tmp-master', cwd: storage_path)
      end
    end

    status
  end
end
