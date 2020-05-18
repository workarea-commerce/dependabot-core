# frozen_string_literal: true

module Dependabot
  class Source
    GITHUB_SOURCE = %r{
      (?<provider>github)
      (?:\.com)[/:]
      (?<repo>[\w.-]+/(?:(?!\.git|\.\s)[\w.-])+)
      (?:(?:/tree|/blob)/(?<branch>[^/]+)/(?<directory>.*)[\#|/])?
    }x.freeze

    GITLAB_SOURCE = %r{
      (?<provider>gitlab)
      (?:\.com)[/:]
      (?<repo>[\w.-]+/(?:(?!\.git|\.\s)[\w.-])+)
      (?:(?:/tree|/blob)/(?<branch>[^/]+)/(?<directory>.*)[\#|/])?
    }x.freeze

    BITBUCKET_SOURCE = %r{
      (?<provider>bitbucket)
      (?:\.org)[/:]
      (?<repo>[\w.-]+/(?:(?!\.git|\.\s)[\w.-])+)
      (?:(?:/src)/(?<branch>[^/]+)/(?<directory>.*)[\#|/])?
    }x.freeze

    AZURE_SOURCE = %r{
      (?<provider>azure)
      (?:\.com)[/:]
      (?<repo>[\w.-]+/([\w.-]+/)?(?:_git/)(?:(?!\.git|\.\s)[\w.-])+)
    }x.freeze

    SOURCE_REGEX = /
      (?:#{GITHUB_SOURCE})|
      (?:#{GITLAB_SOURCE})|
      (?:#{BITBUCKET_SOURCE})|
      (?:#{AZURE_SOURCE})
    /x.freeze

    attr_accessor :provider, :repo, :directory, :branch, :commit,
                  :hostname, :api_endpoint

    def self.from_url(url_string)
      return unless url_string&.match?(SOURCE_REGEX)

      captures = url_string.match(SOURCE_REGEX).named_captures

      new(
        provider: captures.fetch("provider"),
        repo: captures.fetch("repo"),
        directory: captures.fetch("directory"),
        branch: captures.fetch("branch")
      )
    end

    def initialize(provider:, repo:, directory: nil, organization: nil,
                   branch: nil, commit: nil, hostname: nil, api_endpoint: nil)
      if (hostname.nil? ^ api_endpoint.nil?) && (provider != "codecommit")
        msg = "Both hostname and api_endpoint must be specified if either "\
              "are. Alternatively, both may be left blank to use the "\
              "provider's defaults."
        raise msg
      end

      @provider = provider
      @repo = repo
      @directory = directory
      @organization = organization
      @branch = branch
      @commit = commit
      @hostname = hostname || default_hostname(provider)
      @api_endpoint = api_endpoint || default_api_endpoint(provider)
    end

    def url
      "https://" + hostname + "/" + repo
    end

    def url_with_directory
      return url if [nil, ".", "/"].include?(directory)

      case provider
      when "github", "gitlab"
        path = Pathname.new(File.join("tree/#{branch || 'HEAD'}", directory)).
               cleanpath.to_path
        url + "/" + path
      when "bitbucket"
        path = Pathname.new(File.join("src/#{branch || 'default'}", directory)).
               cleanpath.to_path
        url + "/" + path
      when "azure"
        url + "?path=#{directory}"
      when "codecommit"
        raise "The codecommit provider does not utilize URLs"
      else raise "Unexpected repo provider '#{provider}'"
      end
    end

    def organization
      @organization ||= repo.split("/").first
    end

    def project
      raise "Project is an Azure DevOps concept only" unless provider == "azure"

      parts = repo.split("/_git/")
      return parts.first.split("/").last if parts.first.split("/").count == 2

      parts.last
    end

    def unscoped_repo
      repo.split("/").last
    end

    private

    def default_hostname(provider)
      case provider
      when "github" then "github.com"
      when "bitbucket" then "bitbucket.org"
      when "gitlab" then "gitlab.com"
      when "azure" then "dev.azure.com"
      when "codecommit" then "us-east-1"
      when "bitbucket_server" then "bitbucket.com"
      else raise "Unexpected provider '#{provider}'"
      end
    end

    def default_api_endpoint(provider)
      case provider
      when "github" then "https://api.github.com/"
      when "bitbucket" then "https://api.bitbucket.org/2.0/"
      when "bitbucket_server" then "https://bitbucket.com/rest/api/1.0"
      when "gitlab" then "https://gitlab.com/api/v4"
      when "azure" then "https://dev.azure.com/"
      when "codecommit" then nil
      else raise "Unexpected provider '#{provider}'"
      end
    end
  end
end
