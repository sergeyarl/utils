#!/usr/bin/env ruby

# This script sends test emails via local SMTP 
# to various mail services listed in 'providers' hash 
# and then checks if these emails have been delivered

require 'net/imap'
require 'net/smtp'
require 'date'

origin_address = 'test@domain.com'
check_string = 'hKjd2785692cnnfgj2145'
delivery_lag = 1200 # seconds

status_file = "#{File.dirname(__FILE__)}/m_check.status"
lock_file = "#{File.dirname(__FILE__)}/m_check.lock"

status_hash = {}

providers = [{ 'address'     => 'user@ngs.ru',    # done
               'imap_server' => 'mail.ngs.ru',
               'imap_port'   => '143',
               'ssl'         => false,
               'username'    => 'user',
               'password'    => 'pass' },

             { 'address'     => 'user@yahoo.com', # done
               'imap_server' => 'imap.mail.yahoo.com',
               'imap_port'   => '993',
               'ssl'         => true,
               'username'    => 'user@yahoo.com',
               'password'    => 'pass' },

             { 'address'     => 'user@yandex.ru', # done
               'imap_server' => 'imap.yandex.ru',
               'imap_port'   => '993',
               'ssl'         => true,
               'username'    => 'user',
               'password'    => 'pass' },

             { 'address'     => 'user@gmail.com', # done
               'imap_server' => 'imap.gmail.com',
               'imap_port'   => '993',
               'ssl'         => true,
               'username'    => 'user',
               'password'    => 'pass' },

             { 'address'     => 'user@mail.ru', # done
               'imap_server' => 'imap.mail.ru',
               'imap_port'   => '993',
               'ssl'         => true,
               'username'    => 'user@mail.ru',
               'password'    => 'pass' },

             { 'address'     => 'user@rambler.ru', # done
               'imap_server' => 'imap.rambler.ru',
               'imap_port'   => '993',
               'ssl'         => true,
               'username'    => 'user',
               'password'    => 'pass' }]

# Get mailboxes' status from file
def get_status_data(status_file)
  status_hash = {}
  if File.exists?(status_file)
    # check file date
    status_file_ctime = Date._parse(File.mtime(status_file).to_s)
    # parse file only if it is created today
    if status_file_ctime[:mday] == Date.today.mday
      status_file_contents = File.open(status_file, 'a+')
      status_file_contents.each_line do |line|
        if line =~ /^.+?@.+? : [0-9]+$/
           mbox, mbox_status = line.split(' : ')
           status_hash[mbox] = mbox_status.chomp
        end
      end
      status_file_contents.close
    end
  end
  status_hash
end

def send_email(origin_address, rcpt_address, check_string)
  message = <<MESSAGE_END
From: Test mailbox <#{origin_address}>
To: A Test User <#{rcpt_address}>
Subject: mailbox_check: #{check_string}

This is a test e-mail message.
MESSAGE_END

  Net::SMTP.start('localhost', 25) do |smtp|
    smtp.send_message message,
                      origin_address,
                      rcpt_address
  end
end

def check_email(imap_address,
                imap_server,
                imap_port,
                imap_ssl,
                imap_username,
                imap_password,
                status_hash,
                check_string,
                delivery_lag)

  imap_current_status = 0

  # puts "#{imap_username} : #{imap_password}"

  imap = Net::IMAP.new(imap_server, options = { :port => imap_port,
                                                :ssl  => imap_ssl })
  imap.login(imap_username, imap_password)
  imap.select('INBOX')
  imap.search(['ALL'])[0..1000].each do |message_id|
    envelope = imap.fetch(message_id, "ENVELOPE")[0].attr["ENVELOPE"]
    if envelope.subject == "mailbox_check: #{check_string}"
      env_date_uts    = DateTime.parse(envelope.date.to_s).strftime("%s").to_i
      server_date_uts = DateTime.parse(Time.now.to_s).strftime("%s").to_i
      time_diff = server_date_uts - env_date_uts

      if time_diff < delivery_lag
        # puts "#{envelope.from[0].name}: \t#{envelope.subject} " + time_diff.to_s
        # 1 is ok
        imap_current_status = 1
      else
        # mark messages for deletion if they are older than certain time
        # puts "deleting message id: #{message_id}"
        imap.store(message_id, "+FLAGS", [:Deleted])
      end
    end
  end
  # delete marked messages
  imap.expunge

  # set mail box status
  if ! status_hash[imap_address].nil?
    statuslog_failure_count = status_hash[imap_address].to_i
  else
    statuslog_failure_count = 0
  end

  if imap_current_status != 1
    statuslog_failure_count += 1
  end
  status_hash[imap_address] = statuslog_failure_count
  status_hash
end

# write status to status file
def write_report(status_file, status_hash)
  File.open(status_file, 'w') do |f|
    f.write("ADDRESS : TOTAL FAILURES TODAY\n---------------------------------\n")
    status_hash.each do |address, address_status|
      f.write("#{address} : #{address_status}\n")
    end
    f.write("---------------------------------\nReport time: #{Time.now}\n")
  end
end

# check if lock file already exists
if File.exists?(lock_file)
  abort('Already running..')
end

begin
  # Create lock file
  lf = File.open(lock_file, 'w')
  lf.close

  # Get mailboxes' status from file
  status_hash = get_status_data(status_file)

  # Send emails via local SMTP
  providers.each do |prov|
    send_email(origin_address, prov['address'], check_string)
  end

  # Give it a short break :)
  sleep 20

  # Check emails, remove old messages, set status
  providers.each do |prov|
    status_hash = check_email(prov['address'],
                              prov['imap_server'],
                              prov['imap_port'],
                              prov['ssl'],
                              prov['username'],
                              prov['password'],
                              status_hash,
                              check_string,
                              delivery_lag)
  end

  # write status to status file
  write_report(status_file, status_hash)
ensure
  # delete lock file
  if File.exists?(lock_file)
    File.delete(lock_file)
  end
end
