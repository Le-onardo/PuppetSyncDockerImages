require 'net/http'
require 'uri'
require 'json'

Puppet::Functions.create_function(:'sync_docker_images') do
  dispatch :create_docker_registry_instance do
    param 'String', :registry_hostname
    param 'String', :registry_username
    param 'String', :registry_password
    param 'Hash', :image_data
  end

  class DockerRegistry

    def initialize(registry_hostname, registry_username, registry_password, image_data)
      @registry_hostname  = registry_hostname
      @registry_base_url  = "https://#{registry_hostname}"
      @registry_username  = registry_username
      @registry_password  = registry_password
      @image_data         = image_data
    end

    def get_bearer_token(scope)
      uri = URI.parse("#{@registry_base_url}/auth")
      request = Net::HTTP::Post.new(uri)
      request.basic_auth(@registry_username, @registry_password)
      request.set_form_data(
        "account" => @registry_username,
        "scope" => scope,
        "service" => "registry",
      )

      req_options = {
        use_ssl: uri.scheme == "https",
      }

      result = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      return JSON.parse(result.body)['token']
    end

    def request_with_token(location, token, header_return = false, method = 'Get')
      uri = URI.parse("#{@registry_base_url}/v2/#{location}")

      if method == 'Get'
        request = Net::HTTP::Get.new(uri)
      elsif method == 'Delete'
        request = Net::HTTP::Delete.new(uri)
      end

      request["Authorization"] = "Bearer #{token}"

      if header_return
        request["Accept"] = "application/vnd.docker.distribution.manifest.v2+json"
      end

      req_options = {
        use_ssl: uri.scheme == "https",
      }

      result = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      if header_return
        return result.header
      end

      return JSON.parse(result.body)
    end

    def get_repos()
      token = get_bearer_token('registry:catalog:*')
      return request_with_token('_catalog', token)
    end

    def get_tags_for_repo(repo)
      token = get_bearer_token("repository:#{repo}:*")
      tags = request_with_token("#{repo}/tags/list", token)
      if tags['tags'].nil?
        return []
      end
      return tags['tags']
    end

    def get_tag_for_all_repos()
      repos_and_tags = Hash.new()
      get_repos().each do | _, values |
        values.each do | repo |
          repos_and_tags[repo] = get_tags_for_repo(repo)
        end
      end
      return repos_and_tags
    end

    def get_manifests_for_tag(repo, tag)
      token = get_bearer_token("repository:#{repo}:*")
      return request_with_token("#{repo}/manifests/#{tag}", token, true)['Docker-Content-Digest']
    end

    def delete_repo(repo)
      tags = get_tags_for_repo(repo)
      blobs = []
      tags.each do | tag |
        blobs.append(get_manifests_for_tag(repo, tag))
      end

      blobs.each do | blob |
        delete_blob(repo, blob)
      end
    end

    def delete_tag(repo, tag)
      blob = get_manifests_for_tag(repo, tag)
      delete_blob(repo, blob)
    end

    def delete_blob(repo, blob)
      token = get_bearer_token("repository:#{repo}:*")
      return request_with_token("#{repo}/manifests/#{blob}", token, false, 'Delete')
    end

    def sync_repos_and_tags()
      get_tag_for_all_repos().each do | repo, tags |
        if not @image_data.key?(repo)
          puts "Deleting docker registry repo #{repo}"
          delete_repo(repo)
        else
          tags.each do | tag |
            @image_data[repo]['image_tags'].each do | value |
              if value.kind_of?(Hash)
                if not value[:image_tag] == tag
                  puts "Deleting docker registry tag #{tag} for repo #{repo}"
                  delete_tag(repo, tag)
                end
              else
                if not value == tag
                  delete_tag(repo, tag)
                end
              end
            end
          end
        end
      end
    end
  end

  def create_docker_registry_instance(registry_hostname, registry_username, registry_password, image_data)
     instance = DockerRegistry.new(registry_hostname, registry_username, registry_password, image_data)
     instance.sync_repos_and_tags()
  end
end
