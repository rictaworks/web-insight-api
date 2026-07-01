module LogSanitizer
  def self.strip_control_characters(message)
    message.to_s.gsub(/[[:cntrl:]]/, '')
  end
end
