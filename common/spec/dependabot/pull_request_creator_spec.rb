# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator"

RSpec.describe Dependabot::PullRequestCreator do
  subject(:creator) do
    described_class.new(
      source: source,
      base_commit: base_commit,
      dependencies: dependencies,
      files: files,
      credentials: credentials,
      custom_labels: custom_labels,
      reviewers: reviewers,
      assignees: assignees,
      milestone: milestone,
      author_details: author_details,
      signature_key: signature_key
    )
  end

  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "bundler",
      requirements:
        [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }],
      previous_requirements:
        [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
    )
  end
  let(:custom_labels) { nil }
  let(:reviewers) { nil }
  let(:assignees) { nil }
  let(:milestone) { nil }
  let(:author_details) { nil }
  let(:signature_key) { nil }
  let(:source) { Dependabot::Source.new(provider: "github", repo: "gc/bump") }
  let(:files) { [gemfile] }
  let(:base_commit) { "basecommitsha" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: fixture("ruby", "gemfiles", "Gemfile")
    )
  end

  let(:dummy_message_builder) do
    instance_double(described_class::MessageBuilder)
  end
  before do
    allow(described_class::MessageBuilder).
      to receive(:new).and_return(dummy_message_builder)
    allow(dummy_message_builder).
      to receive(:commit_message).
      and_return("Commit msg")
    allow(dummy_message_builder).to receive(:pr_name).and_return("PR name")
    allow(dummy_message_builder).to receive(:pr_message).and_return("PR msg")
  end

  describe "#create" do
    context "without a previous version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "1.5.0",
          package_manager: "bundler",
          requirements: [{
            file: "Gemfile",
            requirement: "~> 1.4.0",
            groups: [],
            source: nil
          }],
          previous_requirements: [{
            file: "Gemfile",
            requirement: "~> 1.4.0",
            groups: [],
            source: nil
          }]
        )
      end

      it "errors out on initialization" do
        expect { creator }.to raise_error(/must have a/)
      end

      context "when the requirements have changed" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            package_manager: "bundler",
            requirements: [{
              file: "Gemfile",
              requirement: "~> 1.4.0",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "Gemfile",
              requirement: "~> 1.3.0",
              groups: [],
              source: nil
            }]
          )
        end

        let(:dummy_creator) { instance_double(described_class::Github) }

        it "delegates to PullRequestCreator::Github with correct params" do
          expect(described_class::Github).
            to receive(:new).and_return(dummy_creator)
          expect(dummy_creator).to receive(:create)
          creator.create
        end

        context "with multiple dependencies" do
          let(:dependencies) { [dependency, dependency] }
          let(:dummy_creator) { instance_double(described_class::Github) }

          it "delegates to PullRequestCreator::Github with correct params" do
            expect(described_class::Github).
              to receive(:new).and_return(dummy_creator)
            expect(dummy_creator).to receive(:create)
            creator.create
          end

          context "one of which has a previous version, the other not" do
            let(:dependencies) { [dependency, dependency_with_lock] }
            let(:dependency_with_lock) do
              Dependabot::Dependency.new(
                name: "business",
                version: "1.5.0",
                previous_version: "1.4.0",
                package_manager: "bundler",
                requirements: [{
                  file: "Gemfile",
                  requirement: "~> 1.5.0",
                  groups: [],
                  source: nil
                }],
                previous_requirements: [{
                  file: "Gemfile",
                  requirement: "~> 1.4.0",
                  groups: [],
                  source: nil
                }]
              )
            end

            it "delegates to PullRequestCreator::Github with correct params" do
              expect(described_class::Github).
                to receive(:new).and_return(dummy_creator)
              expect(dummy_creator).to receive(:create)
              creator.create
            end
          end
        end
      end
    end

    context "with a GitHub source" do
      let(:source) { Dependabot::Source.new(provider: "github", repo: "gc/bp") }
      let(:dummy_creator) { instance_double(described_class::Github) }

      it "delegates to PullRequestCreator::Github with correct params" do
        expect(described_class::Github).
          to receive(:new).
          with(
            source: source,
            branch_name: "dependabot/bundler/business-1.5.0",
            base_commit: base_commit,
            credentials: credentials,
            files: files,
            commit_message: "Commit msg",
            pr_description: "PR msg",
            pr_name: "PR name",
            author_details: author_details,
            signature_key: signature_key,
            custom_headers: nil,
            labeler: instance_of(described_class::Labeler),
            reviewers: reviewers,
            assignees: assignees,
            milestone: milestone,
            require_up_to_date_base: false
          ).and_return(dummy_creator)
        expect(dummy_creator).to receive(:create)
        creator.create
      end
    end

    context "with a GitLab source" do
      let(:source) { Dependabot::Source.new(provider: "gitlab", repo: "gc/bp") }
      let(:dummy_creator) { instance_double(described_class::Gitlab) }

      it "delegates to PullRequestCreator::Github with correct params" do
        expect(described_class::Gitlab).
          to receive(:new).
          with(
            source: source,
            branch_name: "dependabot/bundler/business-1.5.0",
            base_commit: base_commit,
            credentials: credentials,
            files: files,
            commit_message: "Commit msg",
            pr_description: "PR msg",
            pr_name: "PR name",
            author_details: author_details,
            labeler: instance_of(described_class::Labeler),
            approvers: reviewers,
            assignees: nil,
            milestone: milestone
          ).and_return(dummy_creator)
        expect(dummy_creator).to receive(:create)
        creator.create
      end
    end

    context "with an Azure source" do
      let(:source) { Dependabot::Source.new(provider: "azure", repo: "gc/bp") }
      let(:dummy_creator) { instance_double(described_class::Azure) }

      it "delegates to PullRequestCreator::Azure with correct params" do
        expect(described_class::Azure).
          to receive(:new).
          with(
            source: source,
            branch_name: "dependabot/bundler/business-1.5.0",
            base_commit: base_commit,
            credentials: credentials,
            files: files,
            commit_message: "Commit msg",
            pr_description: "PR msg",
            pr_name: "PR name",
            author_details: author_details,
            labeler: instance_of(described_class::Labeler)
          ).and_return(dummy_creator)
        expect(dummy_creator).to receive(:create)
        creator.create
      end
    end

    context "with a Bitbucket Server source" do
      let(:source) do
        Dependabot::Source.new(provider: "bitbucket_server",
                               repo: "projects/gc/repos/bp")
      end
      let(:dummy_creator) { instance_double(described_class::BitbucketServer) }

      it "delegates to PullRequestCreator::BitbucketServer w/ correct params" do
        expect(described_class::BitbucketServer).
          to receive(:new).
          with(
            source: source,
            branch_name: "dependabot/bundler/business-1.5.0",
            base_commit: base_commit,
            credentials: credentials,
            files: files,
            commit_message: "Commit msg",
            pr_description: "PR msg",
            pr_name: "PR name",
            reviewers: reviewers
          ).and_return(dummy_creator)
        expect(dummy_creator).to receive(:create)
        creator.create
      end
    end
  end
end
