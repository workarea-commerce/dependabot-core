# frozen_string_literal: true

require "dependabot/metadata_finders"

module Dependabot
  class PullRequestCreator
    require "dependabot/pull_request_creator/azure"
    require "dependabot/pull_request_creator/bitbucket_server"
    require "dependabot/pull_request_creator/codecommit"
    require "dependabot/pull_request_creator/github"
    require "dependabot/pull_request_creator/gitlab"
    require "dependabot/pull_request_creator/message_builder"
    require "dependabot/pull_request_creator/branch_namer"
    require "dependabot/pull_request_creator/labeler"

    class RepoNotFound < StandardError; end
    class RepoArchived < StandardError; end
    class RepoDisabled < StandardError; end
    class NoHistoryInCommon < StandardError; end

    attr_reader :source, :dependencies, :files, :base_commit,
                :credentials, :pr_message_header, :pr_message_footer,
                :custom_labels, :author_details, :signature_key,
                :commit_message_options, :vulnerabilities_fixed,
                :reviewers, :assignees, :milestone, :branch_name_separator,
                :branch_name_prefix, :github_redirection_service,
                :custom_headers

    def initialize(source:, base_commit:, dependencies:, files:, credentials:,
                   pr_message_header: nil, pr_message_footer: nil,
                   custom_labels: nil, author_details: nil, signature_key: nil,
                   commit_message_options: {}, vulnerabilities_fixed: {},
                   reviewers: nil, assignees: nil, milestone: nil,
                   branch_name_separator: "/", branch_name_prefix: "dependabot",
                   label_language: false, automerge_candidate: false,
                   github_redirection_service: "github-redirect.dependabot.com",
                   custom_headers: nil, require_up_to_date_base: false)
      @dependencies               = dependencies
      @source                     = source
      @base_commit                = base_commit
      @files                      = files
      @credentials                = credentials
      @pr_message_header          = pr_message_header
      @pr_message_footer          = pr_message_footer
      @author_details             = author_details
      @signature_key              = signature_key
      @commit_message_options     = commit_message_options
      @custom_labels              = custom_labels
      @reviewers                  = reviewers
      @assignees                  = assignees
      @milestone                  = milestone
      @vulnerabilities_fixed      = vulnerabilities_fixed
      @branch_name_separator      = branch_name_separator
      @branch_name_prefix         = branch_name_prefix
      @label_language             = label_language
      @automerge_candidate        = automerge_candidate
      @github_redirection_service = github_redirection_service
      @custom_headers             = custom_headers
      @require_up_to_date_base    = require_up_to_date_base

      check_dependencies_have_previous_version
    end

    def check_dependencies_have_previous_version
      return if library? && dependencies.all? { |d| requirements_changed?(d) }
      return if dependencies.all?(&:previous_version)

      raise "Dependencies must have a previous version or changed " \
            "requirement to have a pull request created for them!"
    end

    def create
      case source.provider
      when "github" then github_creator.create
      when "gitlab" then gitlab_creator.create
      when "azure" then azure_creator.create
      when "codecommit" then codecommit_creator.create
      when "bitbucket_server" then bitbucket_server_creator.create
      else raise "Unsupported provider #{source.provider}"
      end
    end

    private

    def label_language?
      @label_language
    end

    def automerge_candidate?
      @automerge_candidate
    end

    def require_up_to_date_base?
      @require_up_to_date_base
    end

    def github_creator
      Github.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: message_builder.commit_message,
        pr_description: message_builder.pr_message,
        pr_name: message_builder.pr_name,
        author_details: author_details,
        signature_key: signature_key,
        labeler: labeler,
        reviewers: reviewers,
        assignees: assignees,
        milestone: milestone,
        custom_headers: custom_headers,
        require_up_to_date_base: require_up_to_date_base?
      )
    end

    def gitlab_creator
      Gitlab.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: message_builder.commit_message,
        pr_description: message_builder.pr_message,
        pr_name: message_builder.pr_name,
        author_details: author_details,
        labeler: labeler,
        approvers: reviewers,
        assignees: assignees,
        milestone: milestone
      )
    end

    def azure_creator
      Azure.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: message_builder.commit_message,
        pr_description: message_builder.pr_message,
        pr_name: message_builder.pr_name,
        author_details: author_details,
        labeler: labeler
      )
    end

    def codecommit_creator
      Codecommit.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: message_builder.commit_message,
        pr_description: message_builder.pr_message,
        pr_name: message_builder.pr_name,
        author_details: author_details,
        labeler: labeler,
        require_up_to_date_base: require_up_to_date_base?
      )
    end

    def bitbucket_server_creator
      BitbucketServer.new(
        source: source,
        branch_name: branch_namer.new_branch_name,
        base_commit: base_commit,
        credentials: credentials,
        files: files,
        commit_message: message_builder.commit_message,
        pr_description: message_builder.pr_message,
        pr_name: message_builder.pr_name,
        reviewers: reviewers
      )
    end

    def message_builder
      @message_builder ||
        MessageBuilder.new(
          source: source,
          dependencies: dependencies,
          files: files,
          credentials: credentials,
          commit_message_options: commit_message_options,
          pr_message_header: pr_message_header,
          pr_message_footer: pr_message_footer,
          vulnerabilities_fixed: vulnerabilities_fixed,
          github_redirection_service: github_redirection_service
        )
    end

    def branch_namer
      @branch_namer ||=
        BranchNamer.new(
          dependencies: dependencies,
          files: files,
          target_branch: source.branch,
          separator: branch_name_separator,
          prefix: branch_name_prefix
        )
    end

    def labeler
      @labeler ||=
        Labeler.new(
          source: source,
          custom_labels: custom_labels,
          credentials: credentials,
          includes_security_fixes: includes_security_fixes?,
          dependencies: dependencies,
          label_language: label_language?,
          automerge_candidate: automerge_candidate?
        )
    end

    def library?
      return true if files.any? { |file| file.name.end_with?(".gemspec") }

      dependencies.any? { |d| !d.appears_in_lockfile? }
    end

    def includes_security_fixes?
      vulnerabilities_fixed.values.flatten.any?
    end

    def requirements_changed?(dependency)
      (dependency.requirements - dependency.previous_requirements).any?
    end
  end
end
