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
  # The work order custom fields chosen in the settings, to fill in at intake, as a ticket draws them. Included
  # by the tickets that print them (Ticket, IntakeForm); #issue is the work order whose values are printed, or
  # nil to leave them all blank.
  module IntakeFields
    # List fields with more choices than this get a line to write on instead
    MAX_CHOICES = 6

    # The chosen custom fields, each as { name:, kind:, value:, choices: }:
    #   yesno    Yes and No boxes (yes/no fields), value '1', '0' or ''
    #   choices  a box for each choice (lists of up to MAX_CHOICES), value the chosen ones
    #   line     a line to write on (anything else), value the field's value
    def fields
      Settings.custom_fields.map { |field| describe_field(field) }
    end

    private

    def describe_field(field)
      raw = issue ? issue.custom_field_value(field) : nil
      case field.field_format
      when 'bool'
        { name: field.name, kind: 'yesno', value: raw.to_s, choices: [] }
      when 'list', 'enumeration'
        choices = field.field_format == 'list' ? field.possible_values : field.enumerations.active.map(&:name)
        chosen = Array(field.cast_value(raw)).map(&:to_s)
        if choices.size.between?(1, MAX_CHOICES)
          { name: field.name, kind: 'choices', value: chosen, choices: choices }
        else
          { name: field.name, kind: 'line', value: chosen.join(', '), choices: [] }
        end
      else
        { name: field.name, kind: 'line', value: line_value(field, raw), choices: [] }
      end
    end

    def line_value(field, raw)
      values = Array(field.cast_value(raw)).compact
      values.map { |value| value.is_a?(Date) ? I18n.l(value) : value.to_s }.join(', ')
    end
  end
end
