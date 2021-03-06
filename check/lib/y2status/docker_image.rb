
require "json"

module Y2status
  # Docker Hub image
  class DockerImage
    include Downloader
    include Reporter

    attr_reader :image, :error

    def initialize(image)
      @image = image
    end

    def builds
      @builds ||= download
    end

    def error?
      error && !error.empty?
    end

    def success?
      !builds.any?(&:failure?)
    end

    def issues
      builds.count(&:failure?)
    end

    def url
      "https://hub.docker.com/r/#{image}/"
    end

    def builds_url
      "https://hub.docker.com/r/#{image}/builds/"
    end

  private

    def docker_status_url
      "https://hub.docker.com/v2/repositories/#{image}/buildhistory/?page_size=100"
    end

    def download
      body = download_url(docker_status_url)

      if body.empty?
        @error = "Cannot download #{docker_status_url}"
        print_error(error)
        return []
      end

      status = JSON.parse(body)

      # remove the duplicates, we need just the latest result for each tag
      results = status["results"]
      results.uniq! { |r| r["dockertag_name"] }

      results.map do |r|
        DockerBuild.new(self, r["dockertag_name"], r["status"])
      end
    end
  end
end
