# -*- encoding: utf-8 -*-
require "outlook_cui/msg_parse"
require "outlook_cui/utility"
require "outlook_cui/version"

require "win32ole"
require "date"

module OutlookCui
  extend self

  Attachment_Only = true
  Save_Dir_Root = "./mail"

  # fix me limit flag
  @limit = false
  @limit_count = 20 

  @f_index = 0
  @folder_list = {}
  @mail_list = {}

  begin
    outlook = WIN32OLE::connect("Outlook.Application")
    @namespace = outlook.getNameSpace("MAPI")
    @folders = @namespace.Folders
  rescue WIN32OLERuntimeError => ex
    puts "Error: Please start Outlook."
    puts "exit."
    puts ex
    exit 1
  end

  def folders(folders=nil)
    if folders.nil? then
      folders = @folders
      @f_index = 0
    else
      folders = folder(folders["entry_id"]).Folders
    end

    folders.each do |folder|
      @f_index += 1
      folder = { "name"     => folder.Name, 
                 "count"    => folder.Items.Count, 
                 "entry_id" => folder.EntryId }
      @folder_list[@f_index.to_s] = folder 

      folders(folder)
      GC.start
    end
    @folder_list
  rescue => ex
    puts "Error: folders"
    puts ex
  end

  def mails(entry_id)
    folder = folder(entry_id)

    index = 0
    max = folder.Items.count

    folder.Items.each do |mail|
      break if @limit and index == @limit_count
      index += 1
      attach_count = mail.Attachments.Count
      sent         = mail.ole_respond_to?("SentOn")             ? mail.SentOn             : "unknown"
      sender       = mail.ole_respond_to?("SenderEmailAddress") ? mail.SenderEmailAddress : "unknown" 
      subject      = mail.ole_respond_to?("Subject")            ? mail.Subject            : "unknown"
      entry_id     = mail.ole_respond_to?("EntryId")            ? mail.EntryId            : "unknown"

      mail = { "attach_count" => attach_count, 
               "sent"         => sent, 
               "sender"       => sender, 
               "subject"      => subject, 
               "entry_id"     => entry_id }
      @mail_list[index.to_s] = mail
      GC.start
      print "\r#{self.rjust(index.to_s)}/#{max} mails read..."
    end
    print "\n"
    @mail_list
  rescue => ex
    puts "Error: mails"
    puts ex
    exit 1
  end

  def save_mail(entry_id, save_dir_root, attachment=true)
    sleep(1)
    mail = mail(entry_id)
    sender_name   = mail.ole_respond_to?("SenderName")         ? mail.SenderName         : "unknown"
    sender_email  = mail.ole_respond_to?("SenderEmailAddress") ? mail.SenderEmailAddress : "unknown"
    to            = mail.ole_respond_to?("To")                 ? mail.To                 : "unknown"
    cc            = mail.ole_respond_to?("CC")                 ? mail.CC                 : "unknown"
    received_time = mail.ole_respond_to?("SentOn")             ? mail.SentOn             : Time.new
    subject       = mail.ole_respond_to?("Subject")            ? mail.Subject            : "unknown"
    body          = mail.ole_respond_to?("Body")               ? mail.Body               : "unknown"

    save_dir_root ||= Save_Dir_Root
    save_dir_root = File.expand_path(save_dir_root)
    # puts "save_dir   : #{save_dir_root}"

    save_dir_name = "#{received_time.strftime("%Y%m%d_%H%M%S")}_#{self.replace(subject)}"
    save_dir = self.pathname(save_dir_root, save_dir_name)

    if FileTest.exist?(save_dir)
      # delete this directory if you want redownload
      puts "skip!      : #{save_dir_name} is exist"
      return
    end
    
    save_file_name = "#{save_dir_name}.txt"
    save_file = self.pathname(save_dir, save_file_name)

    FileUtils.mkdir_p(save_dir) 
    File.open(save_file, "w") do |file|
      file.write "SENDER      : #{sender_name}\n" \
                 "              #{sender_email}\n" \
                 "TO          : #{to}\n" \
                 "CC          : #{cc}\n" \
                 "ReceivedTime: #{received_time}\n" \
                 "SUBJECT     : #{subject}\n" \
                 "BODY        : \n" \
                 "#{body}\n"
    end
    puts "save_mail  : #{subject}"

    if attachment then
      save_attach(entry_id, save_dir)
    end
    GC.start
  rescue => ex
    puts "Error: save_mail"
    puts ex
    exit 1
  end

  def save_attach(entry_id, save_dir)
    # puts "save_dir   : #{save_dir}"
    mail = mail(entry_id)
    attach_count = mail.Attachments.Count 
    attachments  = mail.Attachments

    unless attach_count == 0 then
      attachments.each do |item|
       save_item_name = self.replace(item.FileName)
       save_item = self.pathname(save_dir, save_item_name)

       item.SaveAsFile(save_item)
       puts "save_attach: #{save_item_name}"

       if save_item_name =~ /^.*\.msg/ then
         msg = MsgParse.new
         msg.down(save_item)
       end
      end
    end
  rescue => ex
    puts "Error: save_attachment"
    puts ex
    exit 1
  end

private
  def folder(entry_id)
    @namespace.GetFolderFromID(entry_id)
  end

  def mail(entry_id)
    @namespace.GetItemFromID(entry_id)
  end
end

if $0 == __FILE__ then
end