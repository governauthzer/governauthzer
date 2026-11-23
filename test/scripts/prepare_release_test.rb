require "test_helper"
require "open3"
require Rails.root.join(".github/scripts/prepare_release")

class PrepareReleaseTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join(".github/scripts/prepare_release.rb")
  CHANGELOG = <<~MD
    # Changelog

    ## Unreleased

    ### Added

    - Something new.

    ## 0.5.0 — 2026-07-17

    - Old.
  MD

  test "a final version bumps by patch, minor or major" do
    assert_equal "0.5.1", PrepareRelease.next_version("0.5.0", bump: "patch", beta: false)
    assert_equal "0.6.0", PrepareRelease.next_version("0.5.0", bump: "minor", beta: false)
    assert_equal "1.0.0", PrepareRelease.next_version("0.5.0", bump: "major", beta: false)
  end

  test "beta from a final version is the first beta of the bumped version" do
    assert_equal "1.0.0-beta.1", PrepareRelease.next_version("0.5.0", bump: "major", beta: true)
  end

  test "from a beta, bump is ignored: beta goes to the next beta, no beta releases it" do
    assert_equal "1.0.0-beta.2", PrepareRelease.next_version("1.0.0-beta.1", bump: "patch", beta: true)
    assert_equal "1.0.0", PrepareRelease.next_version("1.0.0-beta.2", bump: "major", beta: false)
  end

  test "an unreadable VERSION or bump is refused" do
    assert_raises(ArgumentError) { PrepareRelease.next_version("1.0", bump: "patch", beta: false) }
    assert_raises(ArgumentError) { PrepareRelease.next_version("1.0.0", bump: "huge", beta: false) }
  end

  test "release notes compare against the last final release" do
    notes = PrepareRelease.release_notes(CHANGELOG, version: "1.0.0-beta.2", repo: "o/r", last_final_tag: "v0.5.0")
    assert_includes notes, "- Something new."
    assert_includes notes, "https://github.com/o/r/compare/v0.5.0...v1.0.0-beta.2"
  end

  test "a beta run bumps VERSION, leaves CHANGELOG alone and reports a prerelease" do
    out, changelog, version = run_script("0.5.0", "major", "true")
    assert_equal "1.0.0-beta.1", version
    assert_equal CHANGELOG, changelog
    assert_includes out, "prerelease=true"
  end

  test "a final run dates the Unreleased section" do
    out, changelog, version = run_script("1.0.0-beta.1", "patch", "false")
    assert_equal "1.0.0", version
    assert_match(/## Unreleased\n\n## 1\.0\.0 — \d{4}-\d{2}-\d{2}\n\n### Added\n\n- Something new\./, changelog)
    assert_includes out, "prerelease=false"
  end

  private

  # The script finds VERSION and CHANGELOG.md relative to itself, so it runs from a
  # copy in a scratch tree.
  def run_script(version, bump, beta)
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, ".github/scripts"))
      FileUtils.cp(SCRIPT, File.join(root, ".github/scripts"))
      File.write(File.join(root, "VERSION"), "#{version}\n")
      File.write(File.join(root, "CHANGELOG.md"), CHANGELOG)
      out, status = Open3.capture2e({ "GITHUB_REPOSITORY" => "o/r" }, "ruby", ".github/scripts/prepare_release.rb",
                                    bump, File.join(root, "notes.md"), beta, chdir: root)
      assert status.success?, out
      [ out, File.read(File.join(root, "CHANGELOG.md")), File.read(File.join(root, "VERSION")).strip ]
    end
  end
end
