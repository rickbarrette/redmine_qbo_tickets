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
      'uppercase' => '1'
    }.freeze

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
  end
end
