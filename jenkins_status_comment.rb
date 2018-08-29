#! /usr/bin/env ruby

# This script parses the "rake osc:sr" output and creates a SR link comment
# at the respective GitHub repository
#
# Usage: Export the GitHub token in the GH_TOKEN environment variable, then run
#   rake osc:sr | tee rake_output
#   ./travis-status-update -l rake_output

require "net/http"
require "uri"
require "json"

# get the  GitHub repository name in the current directory
# @return [String,nil] repository or nil if not found
def git_repo
  url = `git config --get remote.origin.url`
  # e.g. git@github.com:yast/yast-yast2.git
  # or https://github.com/yast/yast-yast2.git
  if url.match(/git@github.com:(.*)\.git/)
    return Regexp.last_match[1]
  else
    url.match(/https:\/\/github.com\/(.*)\.git/)[1]
  end
end

# get the git commit hash for the repository in the current directory
# @return [String,nil] hash or nil if not found
def git_commit
  `git rev-parse HEAD`.chomp
end

def closed_pulls
  # see https://developer.github.com/v3/pulls/
  query  = {
    "state" => "closed",
    "sort" => "updated",
    "direction" => "desc"
  }
  
  http_get("https://api.github.com/repos/#{git_repo}/pulls", query)
end

def pull_details(id)
  http_get("https://api.github.com/repos/#{git_repo}/pulls/id")
end

# Get the pull request for the current Git checkout
# @return [Hash] Parsed GitHub response
#
def git_pr
  # simple case - merged with "Merge" button at GitHub with the default message
  # containing the pull request number
  git_log = `git log -n 1 --oneline`
  if git_log.match(/Merge pull request #(\d+) from/)
    return Regexp.last_match[1]
  end
  
  # get the closed pull requests
  response = closed_pulls
  return nil unless response.is_a?(Net::HTTPSuccess)

  pulls = JSON.parse(response.body)
  commit = git_commit

  # check if the latest commit sha matches any "merge_commit_sha" in the pulls
  pulls.find do |pull|
    pull["merge_commit_sha"] == commit
  end
end

# parse the rake osc:sr output and find the URL of the created repository
# and the context (OBS/IBS)
# @return [Hash<Symbol, String>] SR data
def osc_info(log)
  return unless log =~ /^osc -A '([^']*)'/

  if Regexp.last_match[1] == "https://api.suse.de/"
    link_host = "build.suse.de"
    context = "IBS"
  else
    link_host = "build.opensuse.org"
    context = "OBS"
  end

  return unless log =~ /^created request id ([0-9]+)/

  obs_url = "https://" + link_host + "/request/show/" + Regexp.last_match[1]

  {
    context: context,
    sr:      Regexp.last_match[1],
    url:     obs_url
  }
end

# post the status at GitHub, runs HTTP POST
# @param url [String] GitHub status URL
# @param data [Hash] HTTP data (sent as JSON)
# @return [Net::HTTPResponse] HTTP response
def http_request(url, type, data, query)
  uri = URI.parse(url)
  uri.query = URI.encode_www_form(query) unless query.nil?
  https = Net::HTTP.new(uri.host, uri.port)
  https.use_ssl = true if uri.scheme == "https"

  headers = {
    "Content-Type"  => "text/json"
  }
  headers["Authorization"] = "token #{ENV["GH_TOKEN"]}" if ENV["GH_TOKEN"]

  request = type.new(uri.request_uri, headers)
  request.body = data.to_json unless data.nil?

  print "Sending #{type} request to #{url}..."
  # Send the request
  res = https.request(request)
  if res.is_a?(Net::HTTPSuccess)
    puts " OK"
  else
    puts " Failed: #{res.code}: #{res.body}"
  end

  res
end

# post the status at GitHub, runs HTTP POST
# @param url [String] GitHub status URL
# @param headers [Hash] HTTP headers
# @param data [Hash] HTTP data (sent as JSON)
# @return [Net::HTTPResponse] HTTP response
def http_post(url, headers, data)
  http_request(url, Net::HTTP::Post, data, nil)
end

# post the status at GitHub, runs HTTP POST
# @param url [String] the target URL
# @param data [Hash] the HTTP data, sent as JSON
# @return [Net::HTTPResponse] HTTP response
def http_get(url, query = nil)
  http_request(url, Net::HTTP::Get, nil, query)
end

def parse_log(log, pr)
  unless File.exist?(log)
    $stderr.puts "File #{log} does not exist!"
    exit 1
  end

  info = osc_info(File.read(log))

  unless pr
    return ":heavy_check_mark: [Jenkins job ##{ENV["BUILD_DISPLAY_NAME"]}]" \
      "(#{ENV["BUILD_URL"]}) successfully finished."
  end

  jenkins = " by [Jenkins job #{ENV["BUILD_DISPLAY_NAME"]}](#{ENV["BUILD_URL"]})" if ENV["BUILD_URL"]

  ":heavy_check_mark: Created #{info[:context]} submit " \
      "[request ##{info[:sr]}](#{info[:url]})#{jenkins}."
end

##############################################################################

require 'optparse'

pr = git_pr

if pr.nil?
  puts "ERROR: Cannot find the respective pull request"
  exit 1
end

message = nil
dry_run = false
OptionParser.new do |opts|
  opts.on("-d", "--dry-run", "Dry run (do not send the comment)") do
    dry_run = true
  end

  opts.on("-f", "--failed", "Report build failure") do
    message = ":x: [Jenkins job ##{ENV["BUILD_DISPLAY_NAME"]}](#{ENV["BUILD_URL"]}) failed."
  end

  opts.on("-s", "--success", "Report sucessful build") do
    message = ":heavy_check_mark: [Jenkins job ##{ENV["BUILD_DISPLAY_NAME"]}]" \
      "(#{ENV["BUILD_URL"]}) successfully finished."
  end

  opts.on("-l", "--log=FILE", "Report sucess and send the link for the submit " \
    "request found in the log file") do |f|
    message = parse_log(f, pr)
  end
end.parse!

headers = {
  "Content-Type"  => "text/json",
  "Authorization" => "token #{ENV["GH_TOKEN"]}"
}

url = "https://api.github.com/repos/#{git_repo}/issues/#{pr["number"]}/comments"

if message.nil? || message.empty?
  puts "ERROR: Cannot build a comment message"
  exit 1
end

puts "Pull request: https://github.com/yast/#{git_repo}/pull/#{pr["number"]}"
puts "Comment: #{message}"

exit 0 if dry_run

res = http_post(url, headers, "body" => message)
if res.is_a?(Net::HTTPSuccess)
  puts " Success"
else
  puts " Error #{res.code}: #{res.body}"
  exit(1)
end