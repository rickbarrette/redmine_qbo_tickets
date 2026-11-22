#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQboTickets
  # The plugin's settings (Administration » Plugins » Redmine QBO Tickets plugin » Configure)
  module Settings
    DEFAULTS = {
      # Issue custom fields printed on the ticket, to fill in at intake (in Redmine's order of the fields)
      'custom_field_ids' => [],
      # Lines for handwritten intake notes
      'note_lines' => '5',
      # Customer's name in capitals at the top
      'uppercase' => '1',

      # Appointment reminders, for the customer to take home: the shop's logo (a black and white PNG the width
      # it prints, made on the settings page) and details at the top
      'logo' => '',
      'shop_name' => '',
      'shop_address' => '',
      'shop_phone' => '',
      'shop_website' => '',
      # Printed at the bottom, e.g. how to reschedule
      'reminder_message' => 'Please call us if you need to reschedule.',
      # The QR code: calendar (adds the appointment to the customer's phone calendar), website or none
      'reminder_qr' => 'calendar',
      # Whether the appointment's notes are printed (they're often written for the shop, not the customer)
      'reminder_notes' => '0'
    }.freeze

    REMINDER_QR = %w[calendar website none].freeze
    # The logo's largest size: as wide as the paper's printable width, and not too tall
    LOGO_MAX_WIDTH = 548
    LOGO_MAX_HEIGHT = 320
    LOGO_PREFIX = 'data:image/png;base64,'
    # A 1-bit PNG of the largest logo is under 30KB as base64 (the settings are stored in one text column)
    LOGO_MAX_LENGTH = 40_000

    def self.values
      DEFAULTS.merge((Setting.plugin_redmine_qbo_tickets.presence || {}).to_h.stringify_keys)
    end

    def self.custom_field_ids
      Array(values['custom_field_ids']).map(&:to_i).select(&:positive?)
    end

    # The chosen issue custom fields, in Redmine's order
    def self.custom_fields
      ids = custom_field_ids
      ids.empty? ? [] : IssueCustomField.where(id: ids).sorted.to_a
    end

    def self.note_lines
      (Integer(values['note_lines'].to_s, exception: false) || DEFAULTS['note_lines'].to_i).clamp(0, 20)
    end

    def self.uppercase?
      values['uppercase'].to_s == '1'
    end

    # The logo as a data: URL, when it's a PNG no larger than the paper; else nil
    def self.logo
      value = values['logo'].to_s
      return nil if value.blank? || value.length > LOGO_MAX_LENGTH || !value.start_with?(LOGO_PREFIX)

      png = Base64.strict_decode64(value.delete_prefix(LOGO_PREFIX))
      width, height = png_size(png)
      width && width <= LOGO_MAX_WIDTH && height <= LOGO_MAX_HEIGHT ? value : nil
    rescue ArgumentError
      nil
    end

    # A PNG's [width, height], or nil when it isn't one
    def self.png_size(png)
      return nil unless png.start_with?("\x89PNG\r\n\x1A\n".b) && png.byteslice(12, 4) == 'IHDR'

      png.byteslice(16, 8).unpack('NN')
    end

    def self.shop_name
      values['shop_name'].to_s.squish
    end

    # The address's lines, without blank ones
    def self.shop_address_lines
      values['shop_address'].to_s.split(/\r?\n/).map(&:squish).compact_blank
    end

    def self.shop_phone
      values['shop_phone'].to_s.squish
    end

    def self.shop_website
      values['shop_website'].to_s.squish
    end

    def self.reminder_message
      values['reminder_message'].to_s.gsub(/\r\n?/, "\n").strip
    end

    def self.reminder_qr
      REMINDER_QR.include?(values['reminder_qr'].to_s) ? values['reminder_qr'].to_s : DEFAULTS['reminder_qr']
    end

    def self.reminder_notes?
      values['reminder_notes'].to_s == '1'
    end
  end
end
