#!/usr/bin/env ruby

require "json"

# cache the read repos from Github
CACHE_FILE = ".yast_repos_cache.json"
# 2 weeks
CACHE_TIMEOUT = 60*60*24*14

def read_yast_cache
  if File.exist?(CACHE_FILE) && File.stat(CACHE_FILE).mtime + CACHE_TIMEOUT > Time.now
    return JSON.parse(File.read CACHE_FILE)
  end

  repos = JSON.parse(`curl -s 'https://api.github.com/orgs/yast/repos?page=1&per_page=100'`).map{|r| r["name"]}
  repos += JSON.parse(`curl -s 'https://api.github.com/orgs/yast/repos?page=2&per_page=100'`).map{|r| r["name"]}

  repos.sort!

  File.write(CACHE_FILE, JSON.generate(repos))

  repos
end


repos = read_yast_cache
puts "Found #{repos.size} Yast repositories"

IGNORE = [
"yast-backup",
"yast-bluetooth",
"yast-boot-server",
"yast-cd-creator",
"yast-certify",
"yast-cim",
"yast-databackup",
"yast-dbus-client",
"yast-debugger",
"yast-dialup",
"yast-dirinstall",
"yast-fax-server",
"yast-fingerprint-reader",
"yast-heartbeat",
"yast-hpc",
"yast-ipsec",
"yast-irda",
"yast-liby2util",
"yast-meta",
"yast-mouse",
"yast-mysql-server",
"yast-ntsutils",
"yast-oem-installation",
"yast-online-update-test",
"yast-openschool",
"yast-openteam",
"yast-openwsman-yast",
"yast-packagemanager",
"yast-packagemanager-test",
"yast-phone-services",
"yast-power-management",
"yast-profile-manager",
"yast-registration",
"yast-repair",
"yast-restore",
"yast-squidguard",
"yast-sshd",
"yast-sudo",
"yast-support",
"yast-system-profile",
"yast-system-update",
"yast-ui-qt-tests",
"yast-uml",
"yast-you-server",
"yast-yxmlconv",
"yast-y2pmsh",
"yast-y2r-tools",
]

repos = repos - IGNORE
puts "Ignoring #{IGNORE.size} obsoleted repositories, using #{repos.size} repositories"

repos.each do |repo|
  if File.exist? repo
    puts "Updating #{repo}..."

    Dir.chdir repo do
      `git checkout -q master`
      `git fetch --prune`
      `git pull --rebase`
    end
  else
    puts "Cloning #{repo}..."
    `git clone git@github.com:yast/#{repo}.git`
  end

end


