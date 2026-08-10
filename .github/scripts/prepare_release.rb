#!/usr/bin/env ruby
# frozen_string_literal: true

# Prepares a release, driven by .github/workflows/release.yml:
#
#   1. bumps VERSION by patch / minor / major
#   2. turns the CHANGELOG's "Unreleased" section into a dated one for the new
#      version
#   3. writes the GitHub Release body — that section plus a compare link — to the
#      path given as the second argument
#
# Prints `key=value` lines for GITHUB_OUTPUT. Touches no git state — the
# workflow commits, tags and pushes, so a failed image build leaves nothing
# behind.
#
#   ruby .github/scripts/prepare_release.rb patch /tmp/notes.md

bump = ARGV.fetch(0)
notes_path = ARGV.fetch(1)

root = File.expand_path("../..", __dir__)
version_file = File.join(root, "VERSION")
changelog_file = File.join(root, "CHANGELOG.md")

major, minor, patch = File.read(version_file).strip.split(".").map(&:to_i)
case bump
when "major" then major, minor, patch = major + 1, 0, 0
when "minor" then minor, patch = minor + 1, 0
when "patch" then patch += 1
else abort "unknown bump #{bump.inspect} — expected patch, minor or major"
end
version = [ major, minor, patch ].join(".")

# What shipped, in the maintainer's words — the CHANGELOG's Unreleased section,
# written while making the change. Deliberately no generated commit list: it
# repeats in prose what the compare link below shows properly.
changelog = File.read(changelog_file)
unreleased_section = /^## Unreleased\n.*?(?=^## |\z)/m
written = changelog[unreleased_section].to_s
              .sub(/^## Unreleased\n/, "")
              .strip
written = "No changes recorded." if written.empty?

entry = "## #{version} — #{Time.now.strftime('%Y-%m-%d')}\n\n#{written}\n"
# Block form: the notes may contain backslash sequences that the string form of
# sub would read as backreferences.
changelog = changelog.sub(unreleased_section) { "## Unreleased\n\n#{entry}\n" }

# The release page gets one thing the CHANGELOG does not: a link to every commit
# in the range, so nothing is hidden without listing it all inline. A first
# release has no previous tag to compare against — point at the tag's own history.
repo = ENV["GITHUB_REPOSITORY"] || `git remote get-url origin`[%r{github\.com[:/](.+?)(?:\.git)?\s*\z}, 1]
last_tag = `git describe --tags --abbrev=0 2>/dev/null`.strip
path = $?.success? && !last_tag.empty? ? "compare/#{last_tag}...v#{version}" : "commits/v#{version}"

notes = written.dup
notes << "\n\n**Full Changelog**: https://github.com/#{repo}/#{path}" if repo

File.write(version_file, "#{version}\n")
File.write(changelog_file, changelog)
File.write(notes_path, "#{notes}\n")

puts "version=#{version}"
puts "major=#{major}"
puts "major_minor=#{major}.#{minor}"
