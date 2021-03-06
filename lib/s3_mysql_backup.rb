require "net/smtp"
require "time"
require 'fileutils'
require 'yaml'
require 'erb'

require File.dirname(__FILE__) + '/s3utils'

#
class S3MysqlBackup
  
  def initialize(db_name, path_to_config)
    @db_name        = db_name
    @path_to_config = path_to_config

    self
  end
  
  def run
    ensure_backup_dir_exists

    connect_to_s3

    remove_old_backups
    
    mail_notification(dump_db)
  end
  
  
  protected
  
  def config
    @s3config ||= YAML.load(ERB.new(File.read(@path_to_config)).result)
  end

  def connect_to_s3
    @s3utils ||= S3Utils.new(config['s3_access_key_id'], config['s3_secret_access_key'], config['s3_bucket'])
  end

  # make the DB backup file
  def dump_db
    filename  = Time.now.strftime("#{@backup_dir}/#{@db_name}.%Y%m%d.%H%M%S.sql.gz")
    host = config['dump_host'] || 'localhost'
    mysqldump = `which mysqldump`.to_s.strip
    `#{mysqldump} #{config['dump_opts']} --host=#{host} --user=#{config['dump_user']} --password=#{config['dump_pass']} #{@db_name} | gzip > #{filename}`
    @s3utils.store(filename)
    filename
  end

  def ensure_backup_dir_exists
    @backup_dir = File.expand_path(config['backup_dir'])
    FileUtils.mkdir_p @backup_dir
  end

  def human_size(num, unit='bytes')
    units = %w(bytes KB MB GB TB PB EB ZB YB)
    if num <= 1024
      "#{"%0.2f"%num} #{unit}"
    else
      human_size(num/1024.0, units[units.index(unit)+1])
    end
  end

  def mail_notification(filename)
    stats = File.stat(filename)
    subject = "sql backup: #{@db_name}: #{human_size(stats.size)}"

    content = []
    content << "From: #{config['gmail_user']}"
    content << "To: #{config['mail_to']}"
    content << "Subject: #{subject}"
    content << "Date: #{Time.now.rfc2822}"
    content << "\n#{File.basename(filename)}\n" # body
    content = content.join("\n")

    smtp = Net::SMTP.new("smtp.gmail.com", 587)
    smtp.enable_starttls
    smtp.start("smtp.gmail.com", config['gmail_user'], config['gmail_pass'], :login) do
      smtp.send_message(content, config['gmail_user'], config['mail_to'])
    end
  end

  # remove old backups
  #   - keep 30 days complete
  #   - keep 90 days weekly beyond that
  #   - keep only monthly after that
  def remove_old_backups
    today   = Date.today
    weekly  = (today - 30)
    monthly = (today - 120)

    Dir["#{config['backup_dir']}/*.sql.gz"].each do |name|
      date     = name.split('.')[1]
      filedate = Date.strptime(date, '%Y%m%d')

      if filedate < weekly && filedate >= monthly
        # keep weeklies and also first of month
        unless filedate.wday == 0 || filedate.day == 1
          FileUtils.rm_f(name) if config['keep_local']
          @s3utils.delete(name)
        end
      elsif filedate < monthly
        # delete all old local files
        FileUtils.rm_f(name) if config['keep_local']

        # keep just first of month in S3
        unless filedate.day == 1
          @s3utils.delete(name)
        end
      end

      # don't keep backups locally (on server)
      FileUtils.rm_f(name) unless config['keep_local']

    end # Dir.each
  end # remove_old_backups

end
