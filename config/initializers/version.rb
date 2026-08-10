# The running version, read from the VERSION file at the repo root — the single
# source of truth, bumped by .github/workflows/release.yml and stamped into the
# image's org.opencontainers.image.version label by the same run.
#
# Surfaced on the operator dashboard (so an operator can see what is deployed
# without a shell into the container) and nowhere public: an unauthenticated
# version banner only helps someone matching a host against a CVE list.
Governauthzer::VERSION = begin
  Rails.root.join("VERSION").read.strip.presence || "unknown"
rescue Errno::ENOENT
  "unknown"
end.freeze
