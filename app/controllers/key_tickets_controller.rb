#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# The Print key ticket dialog, opened from an appointment (new): the browser draws the ticket, shows it, and
# sends the picture to a receipt printer's queue (create, redmine_qbo_labels' LabelJob.queue_image); the dialog
# then follows the print job until it's printed (show). The dialog asks for JSON with an Accept header, not a
# .json URL: Redmine treats .json as the REST API, without the session.
class KeyTicketsController < ApplicationController
  before_action :authorize_global
  before_action :find_ticket, only: [:new, :create]
  before_action :find_printers, only: [:new, :create]

  MAX_COPIES = 5

  def new
    respond_to { |format| format.js }
  end

  def create
    printer = @printers.find { |p| p.id == params[:printer_id].to_i } || @printers.first
    return render(json: { errors: [l(:text_qbo_tickets_no_printers)] }, status: :unprocessable_entity) unless printer

    job = LabelJob.queue_image(printer: printer, png: decode_png(params[:image]), title: @ticket.title,
                               copies: params[:copies].to_i.clamp(1, MAX_COPIES), user: User.current,
                               source_type: 'appointment', source_id: @ticket.appointment.id)
    if job.persisted?
      render json: { url: key_ticket_path(job), printer: printer.name, printer_online: printer.online? }
    else
      render json: { errors: job.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # A ticket's print job, for the dialog: only the user's own (or any, for admins)
  def show
    job = LabelJob.without_image.find_by(id: params[:id], source_type: 'appointment')
    return render_404 unless job && (job.user_id == User.current.id || User.current.admin?)

    unless job.finished?
      LabelJob.expire_lapsed
      job = LabelJob.without_image.find(job.id)
    end
    render json: { id: job.id, status: job.status, status_label: job.status_label, error: job.error,
                   finished: job.finished?, printer_online: job.label_printer.online? }
  end

  private

  def find_ticket
    @ticket = RedmineQboTickets::Ticket.find(params[:appointment_id])
    render_404 unless @ticket
  end

  def find_printers
    @printers = LabelPrinter.active.receipts.sorted.to_a
  end

  # The canvas' picture: a data: URL (data:image/png;base64,...) or plain base64
  def decode_png(value)
    Base64.strict_decode64(value.to_s.sub(%r{\Adata:image/png;base64,}, ''))
  rescue ArgumentError
    ''
  end
end
