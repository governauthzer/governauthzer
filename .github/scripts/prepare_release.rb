#!/usr/bin/env ruby
# frozen_string_literal: true

# Prepares a release, driven by .github/workflows/release.yml:
#
#   1. bumps VERSION by patch / minor / major — or to a beta of the next version
#   2. for a final release, turns the CHANGELOG's "Unreleased" section into a dated one
#      for the new version; a beta leaves the CHANGELOG alone, so everything it
#      carried still lands in the final release's entry
#   3. writes the GitHub Release body — that section plus a compare link — to the
#      path given as the second argument
#
# Prints `key=value` lines for GITHUB_OUTPUT. Touches no git state — the
# workflow commits, tags and pushes, so a failed image build leaves nothing
# behind.
#
#   ruby .github/scripts/prepare_release.rb patch /tmp/notes.md [beta]

module PrepareRelease
  VERSION_FORMAT = /\A(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?\z/
  UNRELEASED = /^## Unreleased\n.*?(?=^## |\z)/m

  module_function

  # From a final version, `bump` picks the next one and `beta` makes it its first
  # beta. From a beta, `bump` is ignored: the target is already chosen, so `beta`
  # means the next beta of it and no `beta` means releasing it.
  def next_version(current, bump:, beta:)
    match = VERSION_FORMAT.match(current) or raise ArgumentError, "unreadable VERSION #{current.inspect}"
    major, minor, patch = match[1..3].map(&:to_i)
    target = "#{major}.#{minor}.#{patch}"
    return beta ? "#{target}-beta.#{match[4].to_i + 1}" : target if match[4]

    case bump
    when "major" then major, minor, patch = major + 1, 0, 0
    when "minor" then minor, patch = minor + 1, 0
    when "patch" then patch += 1
    else raise ArgumentError, "unknown bump #{bump.inspect} — expected patch, minor or major"
    end
    version = "#{major}.#{minor}.#{patch}"
    beta ? "#{version}-beta.1" : version
  end

  def prerelease?(version) = version.include?("-")

  # What shipped, in the maintainer's words — the CHANGELOG's Unreleased section,
  # written while making the change. Deliberately no generated commit list: it
  # repeats in prose what the compare link shows properly.
  def unreleased_notes(changelog)
    written = changelog[UNRELEASED].to_s.sub(/^## Unreleased\n/, "").strip
    written.empty? ? "No changes recorded." : written
  end

  def roll_changelog(changelog, version, date)
    entry = "## #{version} — #{date}\n\n#{unreleased_notes(changelog)}\n"
    # Block form: the notes may contain backslash sequences that the string form of
    # sub would read as backreferences.
    changelog.sub(UNRELEASED) { "## Unreleased\n\n#{entry}\n" }
  end

  # The release page gets one thing the CHANGELOG does not: a link to every commit
  # in the range. It starts at the last final release, so a beta and the release it
  # leads to both cover everything since then. A first release has no previous tag
  # to compare against — point at the tag's own history.
  def release_notes(changelog, version:, repo:, last_final_tag:)
    notes = unreleased_notes(changelog).dup
    return notes unless repo

    path = last_final_tag ? "compare/#{last_final_tag}...v#{version}" : "commits/v#{version}"
    notes << "\n\n**Full Changelog**: https://github.com/#{repo}/#{path}"
  end
end

if $PROGRAM_NAME == __FILE__
  bump = ARGV.fetch(0)
  notes_path = ARGV.fetch(1)
  beta = ARGV[2] == "beta" || ARGV[2] == "true"

  root = File.expand_path("../..", __dir__)
  version_file = File.join(root, "VERSION")
  changelog_file = File.join(root, "CHANGELOG.md")

  begin
    version = PrepareRelease.next_version(File.read(version_file).strip, bump: bump, beta: beta)
  rescue ArgumentError => e
    abort e.message
  end
  prerelease = PrepareRelease.prerelease?(version)
  changelog = File.read(changelog_file)

  repo = ENV["GITHUB_REPOSITORY"] || `git remote get-url origin`[%r{github\.com[:/](.+?)(?:\.git)?\s*\z}, 1]
  last_final_tag = `git describe --tags --abbrev=0 --exclude '*-*' 2>/dev/null`.strip
  last_final_tag = nil unless $?.success? && !last_final_tag.empty?

  notes = PrepareRelease.release_notes(changelog, version: version, repo: repo, last_final_tag: last_final_tag)

  File.write(version_file, "#{version}\n")
  File.write(changelog_file, PrepareRelease.roll_changelog(changelog, version, Time.now.strftime("%Y-%m-%d"))) unless prerelease
  File.write(notes_path, "#{notes}\n")

  major, minor = version.split(".")
  puts "version=#{version}"
  puts "prerelease=#{prerelease}"
  puts "major=#{major}"
  puts "major_minor=#{major}.#{minor}"
end
