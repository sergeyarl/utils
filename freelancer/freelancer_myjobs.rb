#!/usr/bin/env ruby

# This script searches jobs/myskills/ page on https://www.freelancer.com for new jobs
# and then pushes notifications to MacOS X Notification Center.
# Requirments: MacOS 10.9.x or grater (Actually tested only with 10.9.5)

require 'Mechanize'
require 'pp'
require 'terminal-notifier'
require 'json'
require 'yaml'

config = YAML::load_file("#{File.dirname(__FILE__)}/freelancer_myjobs.conf")

jobs_filename = config['default']['jobs_filename'] 
jobs_file = "#{File.dirname(__FILE__)}/#{jobs_filename}"

site_url = 'https://www.freelancer.com'
auth_url = "users/ajaxonlogin.php"
jobs_url = 'jobs/myskills/'

username = config['credentials']['freelancer_username']
password = config['credentials']['freelancer_password']

jobs_num = config['default']['jobs_to_display']

exclude_skills = config['default']['exclude_skills']

jobs_array = []

# Get viewed job IDs from file
jobs_file = File.open(jobs_file, 'a+') 
jobs_file.each_line do |line|
  if line =~ /^\d+/
    jobs_array.push(line.chomp)
  end
end

agent = Mechanize.new
agent.user_agent_alias = 'Mac Safari'
#agent.log = Logger.new('log.txt')

page = agent.post("#{site_url}/#{auth_url}", {
  "username"  => username,
  "passwd"    => password,
  "savelogin" => "on",
  "goto_url"  => ""
})

# Get my skills
page = agent.get("#{site_url}/#{jobs_url}")
my_jobs_ids = /ns\.user_jobs.+\[(\d+(\,\d+)*)\]/.match(page.body)[1].gsub(',', '%2C')

# Get ids of skills to exclude
# Skills mapping is stored in the variable 'mapped_jobs'. JSON. 
skills_mapped = /var mapped_jobs = ({.+});/.match(page.body)[1]
skills_mapped_hash = JSON.parse(skills_mapped) 
exclude_skills_ids = []
skills_mapped_hash.each do |key, val|
  exclude_skills.each do |skill|
    if val['name'] == skill
      exclude_skills_ids.push(val['id'])
    end
  end
end

# Double check this url !!!!
page = agent.get("#{site_url}/ajax/table/project_contest_datatable.php?sEcho=1&iColumns=35&sColumns=&iDisplayStart=0&iDisplayLength=#{jobs_num}&iSortingCols=1&iSortCol_0=6&sSortDir_0=desc&keyword=&featured=false&fulltime=false&nda=false&qualified=false&sealed=false&urgent=false&guaranteed=false&highlight=false&private=false&top=false&type=false&budget_min=false&budget_max=false&contest_budget_min=false&contest_budget_max=false&hourlyrate_min=false&hourlyrate_max=false&skills_chosen=#{my_jobs_ids}&verified_employer=false&bidding_ends=N%2FA&bookmarked=false&countries=false&languages=en%2Cru&hourlyProjectDuration=false&advancedFilterPanelView=&disablePushState=false&pushStateRoot=%2Fjobs%2Fmyskills&lat=false&lon=false&local=false&location=%5Bobject+Object%5D&ul=en&uc=1&xpbonus_catIds=#{my_jobs_ids}&jobIdEnable=on&status=open")

jobs_hash = JSON.parse(page.body)

result_id = 0
jobs_hash['aaData'].each do |key|
  result_id += 1

  job_id = key[0].to_s
  job_name = key[1]
  job_desc = key[2]
  job_skills = key[4]
  job_skills_array = job_skills.split(/\s*,\s*/)
  job_href = key[21]

  # Skip the job if we have already shown it
  next if jobs_array.any? { |id| job_id.include?(id) }

  # Skip the job if it has excluded skills
  next if exclude_skills_ids.any? { |id| job_skills_array.include?(id) }

  # Add new job ID to jobs_array
  jobs_array.push(job_id)

#  print "#{result_id}: \tjob name: #{job_name}\n"
#  print "\tjob href: #{site_url}#{job_href}\n"
#  print "\tjob ID: #{job_id}\n"
#  print "\tjob skills: #{job_skills}\n"
#  print "\tjob text: #{job_desc}\n\n\n" 

  # Send notification via terminal-notifier
  TerminalNotifier.notify( job_desc,
                           :title   => "#{job_name}", 
                           :sound   => "Submarine",
                           :appIcon => "#{site_url}/favicon.ico",
                           :open    => "#{site_url}#{job_href}" )
end

File.open(jobs_file, 'r+') do |f|
  jobs_array.each do |job_id|
    f.write("#{job_id}\n")
  end
end
