#!/usr/bin/env ruby

require 'Mechanize'
require 'parseconfig'
require 'terminal-notifier'

site_url = 'https://www.upwork.com'
auth_url = "/Login"
jobs_url = '/find-work-home/?'

jobs_file = "#{File.dirname(__FILE__)}/jobs.txt"

config = ParseConfig.new("#{File.dirname(__FILE__)}/upwork_myjobs.conf")

username = config['upwork_username']
password = config['upwork_password'] 

jobs_array = []

# Get viewed job IDs from file
jobs_file = File.open(jobs_file, 'a+') 
jobs_file.each_line do |line|
  if line =~ /^job_/
    jobs_array.push(line.chomp)
  end
end

agent = Mechanize.new
agent.user_agent_alias = 'Mac Safari'

page = agent.get("#{site_url}#{auth_url}")

form = agent.page.forms.first

# <input type="text" class="form-control ng-pristine ng-invalid ng-invalid-required ng-touched" id="login_username" name="login[username]" required="required" data-ng-model="username" placeholder="Username or Email">

form.field_with(:name => "login[username]").value = username

# <input type="password" class="form-control ng-pristine ng-invalid ng-invalid-required ng-touched" id="login_password" name="login[password]" required="required" data-ng-model="password" placeholder="Password">

form.field_with(:name => "login[password]").value = password

page = form.submit form.buttons.first

jobs_page = agent.get("#{site_url}#{jobs_url}")

#<article class="oMed oJobTile jsSimilarTile" id="some id" ... >
#<h1 class="oRowTitle oH3">
#  <a class="oVisitedLink" href="somehref">some name</a></h1>
#...
#<div class="oDescription"> some description   
#</div>
#...
#</article>

result_id = 0
jobs_page.search("//article[@class='oMed oJobTile jsSimilarTile']").each do |node|
  result_id += 1
  job_id = node[:id].chomp

  # Check if we have already shown this particular job ID
  next if jobs_array.any? { |id| job_id.include?(id) }

  # Add new job ID to jobs_array
  jobs_array.push(job_id)

  # Get various info from HTML
  job_link = node.xpath("//article[@id='#{job_id}']/h1/a")
  job_href = job_link.first[:href].gsub!(/%7E/,'~')
  job_name = job_link.first.content.chomp
  job_desc_simple = node.xpath("//article[@id='#{job_id}']/div[@class='oDescription']")
  job_desc_full = node.xpath("//article[@id='#{job_id}']/div[@class='oDescription']/div[@class='jsFull isHidden']/div[1]")

  # Check with at_xpath if full description is available
  # otherwise show short description
  if node.at_xpath("//article[@id='#{job_id}']/div[@class='oDescription']/div[@class='jsFull isHidden']/div[1]")
    job_desc = job_desc_full.first.content.chomp
  else
    job_desc = job_desc_simple.first.content.chomp.gsub(/\n/, '').gsub(/^ */, '')
  end
#
#  print "#{result_id}: \tjob name: #{job_name}\n"
#  print "\tjob href: #{site_url}#{job_href}\n"
#  print "\tjob ID: #{job_id}\n"
#  print "\tjob text: #{job_desc}\n\n\n" 

  # Send notification via terminal-notifier
  TerminalNotifier.notify( job_desc,
                           :title   => "Upwork: #{job_name}", 
                           :sound   => "Submarine",
                           :appIcon => "#{site_url}/favicon.ico",
                           :open    => "#{site_url}#{job_href}" )
end

File.open(jobs_file, 'r+') do |f|
  jobs_array.each do |job_id|
    f.write("#{job_id}\n")
  end
end
