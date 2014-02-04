require 'optparse'
require 'rugged'
require 'etc'

class CTF3::Level::Level1::UpdateHook
  include Chalk::Log

  class ValidationError < StandardError; end

  LEVEL = 1
  LEDGER = 'LEDGER.txt'
  DIFFICULTY = 'difficulty.txt'
  COMPLETE = 'COMPLETE.state'

  def self.main
    begin
      run
    rescue SystemExit
      raise
    rescue Exception => e
      key = Chalk::Tools::StringUtils.randkey('err')
      log.error('Something went wrong in pushing', e, key: key)
      puts "Something went wrong while pushing your code! Please try back in a few moments. If this error persists, please contact ctf@stripe.com, providing this error message, complete with error key: #{key}"
      exit(1)
    end
  end

  def self.run
    options = {}
    optparse = OptionParser.new do |opts|
      opts.banner = "Usage: #{$0} [options] REF OLD_SHA1 NEW_SHA1"

      opts.on('-h', '--help', 'Display this message') do
        puts opts
        exit(1)
      end
    end
    optparse.parse!

    if ARGV.length != 3
      puts optparse
      return 1
    end

    runner = self.new(*ARGV)
    runner.run
  end

  def initialize(ref, old_sha1, new_sha1)
    @repository = Rugged::Repository.new('.')

    @ref = ref
    @old_sha1 = old_sha1
    @new_sha1 = new_sha1

    load_difficulty
  end

  def lockfile
    File.join('locks', @new_sha1)
  end

  def load_difficulty
    old_commit = @repository.lookup(@old_sha1)
    difficulty_spec = old_commit.tree.get_entry(DIFFICULTY)
    difficulty = @repository.lookup(difficulty_spec[:oid])
    @difficulty = difficulty.content.chomp
  end

  def validate(condition, message)
    raise ValidationError.new(message) unless condition
  end

  def report(message)
    $stderr.puts
    $stderr.puts(message)
    $stderr.puts
  end

  def run
    unless CTF3::Unix.ctf_user?
      if File.exists?(lockfile)
        msg = "Skipping update hook for non-CTF user. Aborting since lockfile present."
        status = 12
      else
        msg = "Skipping update hook for non-CTF user. Lockfile absent."
        status = 0
      end

      $stderr.puts(msg)
      log.info(msg, lockfile: lockfile)
      return status
    end


    $stderr.puts "==================="
    begin
      do_run
    rescue ValidationError => e
      report(e)
      status = 1
    else
      status = 0
    end
    $stderr.puts "==================="

    status
  end

  def master?
    @ref == 'refs/heads/master'
  end

  def round_repo?
    File.exists?('NAME')
  end

  def round_name
    File.read('NAME')
  end

  def validate_ref
    if round_repo?
      validate(master?, "You can only push to the master branch in the round repository.")
    else
      # Personal per-level repo
      if !master?
        report("(Note: you're welcome to try out pushing to non-master branches, but you'll only get leaderboard points by pushing to master.)")
      end
    end
  end

  def get_and_validate_commit
    validate(@new_sha1 != '0000000000000000000000000000000000000000',
      "Deleting the master branch isn't allowed (nice try though!).")
    validate(@new_sha1 < @difficulty,
      "Your commit's SHA1 (#{@new_sha1}) is not lexicographically smaller than #{@difficulty} (the contents of #{DIFFICULTY}). Unfortunately, that's not worth any Gitcoins. Please try again!")

    begin
      commit = @repository.lookup(@new_sha1)
    rescue Rugged::InvalidError => e
      log.error('Rugged parse error', message: e.to_s)
      validate(false, "We couldn't parse your commmit: #{e.message}. (We're using Rugged for our parsing, which may behave differently on edge cases than stock Git. This message probably indicates your commit is malformed. Perhaps you're missing a committer field.)")
    end
    validate(commit.is_a?(Rugged::Commit), "You can't update this ref to a non-commit.")
    commit
  end

  def get_and_validate_parent(commit)
    unless commit.parents.length == 1
      validate(commit.parents.length != 0, "You can't push a new base commit.")
      validate(false, 'Merge commits are not allowed, sorry :(.')
    end
    parent = commit.parents.first

    if master? && parent.oid != @old_sha1
      merge_base = @repository.merge_base(parent.oid, @old_sha1)
      is_ancestor = merge_base == @old_sha1
      validate(is_ancestor, "Sorry, looks like someone else beat you to the punch. Your commit has the wrong parent (#{parent.oid} rather than #{@old_sha1}). You should `git fetch && git reset --hard origin/master` in order to reset to the current head commit.")
      validate(false, "You can only submit one commit at a time. You can `git fetch && git reset --hard origin/master` to get back to the current head commit.")
    end

    parent
  end

  def get_and_validate_diff(parent, commit)
    diff = @repository.diff(parent, commit)
    unless diff.deltas.length == 1
      validate(diff.deltas.length != 0, "You need to change something. In particular, update the ledger to give yourself a Gitcoin!")
      validate(false, "You can only make one change (you made #{diff.deltas.count}). In particular, update the ledger to give yourself a Gitcoin!")
    end
    diff
  end

  def get_and_validate_patch(diff)
    patch = diff.patches.first
    validate(patch.delta.old_file[:path] == LEDGER,
      "You can only modify #{LEDGER}. Do it right, and you can give yourself a Gitcoin!")
    [:path, :flags, :mode].each do |attribute|
      validate(patch.delta.old_file[attribute] == patch.delta.new_file[attribute],
        "No changing the ledger's #{attribute}! You should just modify the file to give yourself a Gitcoin.")
    end
    patch
  end

  def get_and_validate_hunk(patch)
    unless patch.hunks.length == 1
      validate(patch.hunks.length != 0, "You need to update the contents of the ledger.")
      validate(false, "You can only make one change to the ledger.")
    end

    hunk = patch.hunks.first
    hunk
  end

  def interpret_hunk(hunk)
    addition = nil
    deletion = nil
    last_line = true
    hunk.each do |line|
      case line.line_origin
      when :deletion
        validate(!deletion, "You can change at most one ledger entry (looks like you churned more than one line).")
        deletion = line
      when :addition
        validate(!addition, "You can add at most one line to the ledger.")
        addition = line
      when :eof_newline_removed
        validate(false, "No removing the trailing newline from the ledger!")
      when :context
        last_line = false if addition
      else
        validate(false, "Unexpected hunk line of type #{line.line_origin}. This is a bug -- please report it to ctf@stripe.com.")
      end
    end

    validate(addition, "You need to add a line to the ledger. How else will you get a Gitcoin?")
    validate(deletion || last_line, "New entries must be appended to the end of the ledger. Yours was added in the middle.")
    [addition, deletion]
  end

  def interpret_changes(addition, deletion)
    added_name, added_amount = parse_entry(addition.content.chomp, "added to ledger")
    if deletion
      deleted_name, deleted_amount = parse_entry(deletion.content.chomp, "removed from ledger")

      validate(added_name == deleted_name, "You tried to change the name on the entry from #{deleted_name} -> #{added_name}, but that's not allowed. You can only add new names, or give a Gitcoin to yourself.")
      validate(added_amount == deleted_amount + 1, "You need to increase the Gitcoin amount by exactly 1. Instead, you changed it from #{deleted_amount} -> #{added_amount}.")

      [added_name, added_amount, deleted_amount]
    else
      validate(added_amount, "When adding a new entry to the Gitcoin file, you need to start with 1 Gitcoin. It looks like you tried to start with #{added_amount} instead.")

      [added_name, added_amount, nil]
    end
  end

  def validate_name(name)
    public_username = CTF3::Unix.public_username
    validate(name == public_username, "Your public username is #{public_username}. You need to use that username in your ledger, rather than #{name}.")
  end

  def validate_name_uniqueness(parent, name)
    ledger_spec = parent.tree.get_entry(LEDGER)
    ledger = @repository.lookup(ledger_spec[:oid])
    content = ledger.content

    header, amounts = CTF3::Level::Level1::Ledger.parse(content)
    validate(amounts.none? {|other_name, _| other_name == name},
      "Your public username, #{name}, already exists in that file. You can only have one entry in the Gitcoin ledger.")
  end

  def parse_entry(entry, description='in the ledger')
    unless entry =~ /\A([\w .@-]+): ([1-9]\d*)\z/
      validate(false, "Invalid line #{description}: #{entry.inspect}. Valid lines are of the form `<name>: <gitcoins>`")
    end
    [$1, $2.to_i]
  end

  def report_changes(name, new_amount, old_amount)
    if master? && !round_repo?
      mark_complete

      score = 50
      CTF3::Submission::RPC::FinalScoreRPC.publish(
        submission_id: CTF3::Utils.generate_submission_id,
        sha: @new_sha1,
        level: LEVEL,
        clone_url: CTF3::Utils.clone_url,
        username: CTF3::Unix.username,
        submitter_hostname: Socket.gethostname,
        build_hostname: nil,
        test_cases: nil,
        build_fetch_urls: nil,
        worker_hostnames: nil,
        submission_directories_on_worker: nil,

        score: score,
        correct: true,
        incorrect_reason: nil,
        extra: {
          round: round_repo?
        }
        )
      addendum = " Your leaderboard score is #{score}."
    elsif round_repo?
      report("Your submission looks valid. Sending it off to the master Gitcoin server...")

      # We'll never clean this up, but who cares.
      FileUtils.touch(lockfile)
      runner = CTF3::Utils.rubysh('git', 'push', 'origin', "#{@new_sha1}:master",
        Rubysh.stdout > CTF3.logfile, Rubysh.stderr > CTF3.logfile, cwd: Dir.pwd).run

      exitstatus = runner.exitstatus
      unless exitstatus == 0
        # Make sure updates are visible on the next clone
        CTF3::Submission::SubmitterShell::Code.invalidate_clone_state(Dir.pwd)

        log.info('Push exited with status', exitstatus: exitstatus)
        report("Couldn't push to the central Gitcoin repository. This most likely means you lost a race, and another client beat out your push. Please try fetching. (If there's nothing available, this is actually a bug in our Gitcoin implementation, and you should let us know at ctf@stripe.com.)")
        # TODO: have a better exit strategy
        exit(exitstatus || 127)
      end
    end

    if old_amount
      report("Congratulations, #{name}! You gain a Gitcoin, bringing your total to #{new_amount}.#{addendum}")
    else
      report("Congratulations, #{name}! You've just earned your first Gitcoin.#{addendum}")
      if master? && !round_repo?
        report("The bots will stop now. You can run `git clone #{CTF3::Unix.username}@#{CTF3.main_domain}:current-round` to go head-to-head against other Gitcoin miners and earn more points.")
      end
    end
  end

  def mark_complete
    # Make sure everyone knows that we're done
    FileUtils.touch(COMPLETE)
    # Copy in relevant objects, since they'll be pruned soon
    CTF3::Utils.rubysh('git', 'repack', '-a').run
  end

  def do_run
    validate_ref
    commit = get_and_validate_commit
    parent = get_and_validate_parent(commit)
    diff = get_and_validate_diff(parent, commit)
    patch = get_and_validate_patch(diff)
    hunk = get_and_validate_hunk(patch)
    addition, deletion = interpret_hunk(hunk)
    name, new_amount, old_amount = interpret_changes(addition, deletion)
    validate_name(name)
    # If just updating a line, don't need to check for uniqueness
    validate_name_uniqueness(parent, name) unless deletion
    report_changes(name, new_amount, old_amount)
  end
end
