require 'rails_helper'

RSpec.describe LogSanitizer do
  describe '.strip_control_characters' do
    it 'removes newlines and control characters' do
      expect(described_class.strip_control_characters("abc\ndef\r[FAKE] injected")).to eq('abcdef[FAKE] injected')
    end

    it 'leaves ordinary text untouched' do
      expect(described_class.strip_control_characters('normal message')).to eq('normal message')
    end
  end
end
