# From submission -> build, a request to build this code.
class CTF3::Submission::RPC::BuildRPC < CTF3::Submission::RPC::Structured
  include CTF3::Submission::RPC::Cloneable
  include CTF3::Submission::RPC::Repliable

  queue_name 'ctf.build'
  auto_ack true
  queue_opts({})

  prop :id
  prop :sha
  prop :level
  prop :clone_url
  prop :username
  prop :submitter_hostname
  prop :test_cases
  prop :docker_tag
end
