/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2026 rick barrette
 *
 * Print key ticket dialog (redmine_qbo_tickets): draws an appointment's key ticket the size the receipt printer
 * prints it (576 dots across 72mm), in black and white as it will print, shows it, sends the picture to the
 * printer's queue, and follows the print job until it's printed.
 *
 * The ticket, top to bottom: the customer's name and when they're due (big, to read above the key folder's
 * edge), the appointment's details, the job, the appointment's notes, the work order's custom fields to fill in at intake
 * (Yes/No boxes, choices, or lines to write on), lines for intake notes, a QR code, and when it was printed.
 */
var QboTickets = (function($) {
  'use strict';

  var WIDTH = 576;           // dots across the paper
  var MARGIN = 14;
  var FONT = 'QboTicket, "DejaVu Sans", Arial, sans-serif';
  var BLACK_BELOW = 170;     // gray levels darker than this print black (thin letters stay whole)
  var MAX_HEIGHT = 6000;

  var ticket = null;
  var pollTimer = null;
  var following = null;

  function font(weight, size) {
    return weight + ' ' + size + 'px ' + FONT;
  }

  // The text in lines no wider than maxWidth (long words are broken)
  function wrap(ctx, text, maxWidth) {
    var lines = [], line = '';
    String(text || '').split(/\s+/).filter(Boolean).forEach(function(word) {
      var candidate = line ? line + ' ' + word : word;
      if (ctx.measureText(candidate).width <= maxWidth) { line = candidate; return; }
      if (line) { lines.push(line); }
      while (ctx.measureText(word).width > maxWidth && word.length > 1) {
        var cut = word.length - 1;
        while (cut > 1 && ctx.measureText(word.slice(0, cut)).width > maxWidth) { cut -= 1; }
        lines.push(word.slice(0, cut));
        word = word.slice(cut);
      }
      line = word;
    });
    if (line) { lines.push(line); }
    return lines;
  }

  // The largest size (up to max) at which the text fits the width in one line
  function fitSize(ctx, text, weight, max, min, width) {
    var size = max;
    ctx.font = font(weight, size);
    while (size > min && ctx.measureText(text).width > width) {
      size -= 2;
      ctx.font = font(weight, size);
    }
    return size;
  }

  var DAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  // e.g. "Sat 11/21/2026 · 4:35 PM", as the appointment's time is written at the top
  function printedAt(date) {
    var hours = date.getHours(), minutes = date.getMinutes();
    return DAYS[date.getDay()] + ' ' + (date.getMonth() + 1) + '/' + date.getDate() + '/' + date.getFullYear() +
      ' · ' + (hours % 12 || 12) + ':' + (minutes < 10 ? '0' : '') + minutes + ' ' + (hours < 12 ? 'AM' : 'PM');
  }

  function runFont(run, size, bold) {
    return (run.i ? 'italic ' : '') + font(run.b || bold ? 700 : 400, size);
  }

  // Styled runs ({ t, b, i, s, c } text, { br } line breaks, { box } checkboxes) laid out in lines no wider than
  // width: [{ tokens: [{ text | box, font, run, w }], width }]
  function layoutRuns(ctx, runs, width, size, bold) {
    var lines = [{ tokens: [], width: 0 }];
    function line() { return lines[lines.length - 1]; }
    function newLine() {
      var last = line();
      while (last.tokens.length && /^\s+$/.test(last.tokens[last.tokens.length - 1].text || '')) {
        last.width -= last.tokens.pop().w;
      }
      lines.push({ tokens: [], width: 0 });
    }
    function push(token) {
      var current = line();
      var space = /^\s+$/.test(token.text || '');
      if (space && !current.tokens.length) { return; }
      if (!space && current.tokens.length && current.width + token.w > width) {
        newLine();
        current = line();
      }
      current.tokens.push(token);
      current.width += token.w;
    }
    runs.forEach(function(run) {
      if (run.br) { newLine(); return; }
      if (run.box !== undefined) { push({ box: true, checked: run.box, w: size + 4, run: run }); return; }
      var runFontText = runFont(run, size, bold);
      ctx.font = runFontText;
      String(run.t || '').split(/(\s+)/).forEach(function(piece) {
        if (!piece) { return; }
        if (/^\s+$/.test(piece)) { piece = ' '; }
        var w = ctx.measureText(piece).width;
        // A word longer than the line is broken
        while (w > width && piece.length > 1) {
          var cut = piece.length - 1;
          while (cut > 1 && ctx.measureText(piece.slice(0, cut)).width > width) { cut -= 1; }
          push({ text: piece.slice(0, cut), font: runFontText, run: run, w: ctx.measureText(piece.slice(0, cut)).width });
          piece = piece.slice(cut);
          w = ctx.measureText(piece).width;
        }
        push({ text: piece, font: runFontText, run: run, w: w });
      });
    });
    return lines;
  }

  // Draws laid-out lines from top; returns the y below them
  function drawLines(ctx, lines, left, top, size, lineHeight, drawBox) {
    var y = top;
    lines.forEach(function(line) {
      var x = left, baseline = y + Math.round(size * 0.8);
      line.tokens.forEach(function(token) {
        if (token.box) {
          drawBox(x, y + 2, size - 2, token.checked);
        } else {
          ctx.font = token.font;
          ctx.fillText(token.text, x, baseline);
          if (token.run.s) { ctx.fillRect(x, baseline - Math.round(size * 0.3), token.w, 2); }
          if (token.run.c && token.text !== ' ') { ctx.fillRect(x, baseline + 4, token.w, 1); }
        }
        x += token.w;
      });
      y += lineHeight;
    });
    return y;
  }

  // Formatted text's blocks (paragraphs, headings, list items, alerts, code, rules), quotes and alerts with a
  // bar down their left; returns the y below them
  function drawBlocks(ctx, blocks, left, top, width, drawBox) {
    var y = top, QUOTE = 22;
    blocks.forEach(function(block, index) {
      var indent = (block.quote || 0) * QUOTE, x = left + indent, w = width - indent, start = y;
      if (block.type === 'hr') {
        ctx.fillRect(x, y + 8, w, 2);
        y += 20;
      } else if (block.type === 'alert') {
        ctx.fillRect(x, y, w, 34);
        ctx.fillStyle = '#fff';
        ctx.font = font(700, 22);
        ctx.fillText('! ' + block.runs.map(function(run) { return run.t; }).join(''), x + 10, y + 25);
        ctx.fillStyle = '#000';
        y += 34;
      } else if (block.type === 'h') {
        var size = block.level === 1 ? 32 : (block.level === 2 ? 29 : 26);
        y = drawLines(ctx, layoutRuns(ctx, block.runs, w, size, true), x, y, size, Math.round(size * 1.2), drawBox);
      } else if (block.type === 'li') {
        var markerX = x + ((block.level || 1) - 1) * 26;
        ctx.font = font(700, 24);
        var markerWidth = block.marker ? Math.max(24, ctx.measureText(block.marker).width + 10) : 0;
        if (block.marker) { ctx.fillText(block.marker, markerX, y + 19); }
        y = drawLines(ctx, layoutRuns(ctx, block.runs, w - (markerX - x) - markerWidth, 24, false),
                      markerX + markerWidth, y, 24, 29, drawBox);
      } else if (block.type === 'code') {
        var codeLines = layoutRuns(ctx, block.runs.map(function(run) { return run.br ? run : { t: run.t }; }), w - 16, 22, false);
        ctx.lineWidth = 2;
        ctx.strokeRect(x + 1, y + 1, w - 2, codeLines.length * 27 + 10);
        y = drawLines(ctx, codeLines, x + 8, y + 6, 22, 27, drawBox) + 6;
      } else {
        y = drawLines(ctx, layoutRuns(ctx, block.runs, w, 24, false), x, y, 24, 29, drawBox);
      }
      // Quote bars beside the block, one per level
      for (var level = 0; level < (block.quote || 0); level += 1) {
        ctx.fillRect(left + level * QUOTE + 4, start - 3, 4, y - start + 6);
      }
      var next = blocks[index + 1];
      var together = next && block.type === 'li' && next.type === 'li' ||
                     next && block.type === 'alert';
      y += together ? 2 : 10;
    });
    return y - 10;
  }

  // Draws the ticket on a tall canvas; returns the height used
  function drawTicket(ctx, data) {
    var x = MARGIN, right = WIDTH - MARGIN, width = right - x, y = MARGIN;
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, WIDTH, MAX_HEIGHT);
    ctx.fillStyle = '#000';
    ctx.strokeStyle = '#000';
    ctx.textBaseline = 'alphabetic';

    function text(str, weight, size, left) {
      ctx.font = font(weight, size);
      ctx.fillText(str, left === undefined ? x : left, y + Math.round(size * 0.8));
    }
    function rule(thickness, gap) {
      y += gap;
      ctx.fillRect(x, y, width, thickness);
      y += thickness + gap;
    }
    function box(left, top, size, checked) {
      ctx.lineWidth = 3;
      ctx.strokeRect(left + 1.5, top + 1.5, size - 3, size - 3);
      if (checked) {
        ctx.beginPath();
        ctx.moveTo(left + 6, top + 6); ctx.lineTo(left + size - 6, top + size - 6);
        ctx.moveTo(left + size - 6, top + 6); ctx.lineTo(left + 6, top + size - 6);
        ctx.lineWidth = 4;
        ctx.stroke();
      }
    }
    function section(title) {
      rule(3, 10);
      text(title, 700, 26);
      y += 36;
    }

    // Who and when, big
    var nameSize = fitSize(ctx, data.name, 700, 112, 36, width);
    var nameLines = nameSize > 36 ? [data.name] : wrap(ctx, data.name, width);
    nameLines.forEach(function(line) { text(line, 700, nameSize); y += Math.round(nameSize * 1.05); });
    if (data.when) {
      var whenSize = fitSize(ctx, data.when, 700, 40, 24, width);
      text(data.when, 700, whenSize);
      y += whenSize + 8;
    }
    ctx.font = font(400, 24);
    text(data.number, 400, 24);
    y += 30;

    // The appointment's details
    rule(3, 6);
    data.details.forEach(function(pair) {
      ctx.font = font(700, 24);
      var label = pair[0] + ': ';
      var labelWidth = ctx.measureText(label).width;
      text(label, 700, 24);
      ctx.font = font(400, 26);
      var lines = wrap(ctx, pair[1], width - labelWidth);
      lines.forEach(function(line, i) {
        text(line, 400, 26, x + labelWidth);
        y += i < lines.length - 1 ? 30 : 34;
      });
    });

    if (data.job) {
      rule(1, 6);
      ctx.font = font(700, 26);
      wrap(ctx, data.job, width).forEach(function(line) { text(line, 700, 26); y += 32; });
    }

    // The appointment's notes, formatted as Redmine formats them (RedmineQboTickets::RichText's blocks)
    if (data.notes && data.notes.length) {
      section(data.labels.appointment_notes);
      y = drawBlocks(ctx, data.notes, x, y, width, box);
    }

    // The work order's custom fields, to fill in at intake
    if (data.fields.length) {
      section(data.labels.intake);
      var boxSize = 34, noX = right - boxSize - 8, yesX = noX - 84, nameWidth = yesX - x - 16;
      var headed = false;
      data.fields.forEach(function(field) {
        if (field.kind === 'yesno') {
          if (!headed) {
            ctx.font = font(700, 20);
            [[data.labels.yes, yesX], [data.labels.no, noX]].forEach(function(column) {
              ctx.fillText(column[0], column[1] + (boxSize - ctx.measureText(column[0]).width) / 2, y + 16);
            });
            y += 24;
            headed = true;
          }
          ctx.font = font(400, 26);
          var lines = wrap(ctx, field.name, nameWidth);
          var top = y;
          lines.forEach(function(line, i) { text(line, 400, 26); y += i < lines.length - 1 ? 30 : 0; });
          box(yesX, top, boxSize, field.value === '1');
          box(noX, top, boxSize, field.value === '0');
          y = Math.max(y + 30, top + boxSize) + 12;
        } else if (field.kind === 'choices') {
          headed = false;
          text(field.name, 400, 26);
          y += 34;
          var left = x + 8;
          ctx.font = font(400, 24);
          field.choices.forEach(function(choice) {
            var choiceWidth = 30 + 8 + ctx.measureText(choice).width + 22;
            if (left + choiceWidth > right && left > x + 8) { left = x + 8; y += 40; }
            box(left, y, 30, field.value.indexOf(choice) >= 0);
            ctx.font = font(400, 24);
            ctx.fillText(choice, left + 38, y + 24);
            left += choiceWidth;
          });
          y += 46;
        } else {
          headed = false;
          ctx.font = font(400, 26);
          var label = field.name;
          var labelWidth = Math.min(ctx.measureText(label).width + 12, width * 0.6);
          var labelLines = wrap(ctx, label, width * 0.6 - 12);
          labelLines.forEach(function(line, i) { text(line, 400, 26); if (i < labelLines.length - 1) { y += 30; } });
          if (field.value) {
            ctx.font = font(700, 26);
            var valueText = wrap(ctx, field.value, width - labelWidth)[0] || '';
            text(valueText, 700, 26, x + labelWidth);
          }
          ctx.fillRect(x + labelWidth, y + 30, right - x - labelWidth, 2);
          y += 48;
        }
      });
    }

    // Lines for handwritten notes
    if (data.note_lines > 0) {
      section(data.labels.intake_notes);
      for (var i = 0; i < data.note_lines; i += 1) {
        y += 46;
        ctx.fillRect(x, y, width, 2);
      }
      y += 24;
    }

    // QR code, with what it does beside it
    if (data.qr && data.qr.url && window.qrcode) {
      rule(3, 10);
      var qr = qrcode(0, 'M');
      qr.addData(data.qr.url);
      qr.make();
      var count = qr.getModuleCount();
      var cell = Math.max(3, Math.floor(200 / count));
      var size = cell * count;
      for (var row = 0; row < count; row += 1) {
        for (var col = 0; col < count; col += 1) {
          if (qr.isDark(row, col)) { ctx.fillRect(x + 8 + col * cell, y + 8 + row * cell, cell, cell); }
        }
      }
      var captionX = x + 8 + size + 20, top = y;
      ctx.font = font(700, 26);
      var caption = wrap(ctx, data.qr.caption, right - captionX);
      y = top + Math.max(8, Math.round((size + 16 - caption.length * 32) / 2));
      caption.forEach(function(line) { text(line, 700, 26, captionX); y += 32; });
      y = top + size + 16;
    }

    // When it was printed, small at the bottom
    if (data.labels.printed) {
      var stamp = data.labels.printed.replace('%{time}', printedAt(data.printed_at || new Date()));
      y += 8;
      ctx.font = font(400, 20);
      ctx.fillText(stamp, x + (width - ctx.measureText(stamp).width) / 2, y + 16);
      y += 22;
    }

    return Math.min(MAX_HEIGHT, Math.ceil(y + MARGIN));
  }

  // Black and white, as the printer prints it
  function threshold(ctx, width, height) {
    var image = ctx.getImageData(0, 0, width, height), px = image.data;
    for (var i = 0; i < px.length; i += 4) {
      var gray = 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2];
      var value = (px[i + 3] > 0 && gray < BLACK_BELOW) ? 0 : 255;
      px[i] = px[i + 1] = px[i + 2] = value;
      px[i + 3] = 255;
    }
    ctx.putImageData(image, 0, 0);
  }

  // Draws the ticket into the canvas
  function render(canvas, data) {
    var scratch = document.createElement('canvas');
    scratch.width = WIDTH;
    scratch.height = MAX_HEIGHT;
    var height = drawTicket(scratch.getContext('2d'), data);
    canvas.width = WIDTH;
    canvas.height = height;
    var ctx = canvas.getContext('2d');
    ctx.drawImage(scratch, 0, 0, WIDTH, height, 0, 0, WIDTH, height);
    threshold(ctx, WIDTH, height);
  }

  function dialog() { return $('#qbo-ticket-dialog'); }
  function preview() { return dialog().find('canvas.qbo-ticket-preview')[0]; }

  function redraw() {
    var canvas = preview();
    if (canvas && ticket) { render(canvas, ticket); }
  }

  function initDialog(data) {
    ticket = data;
    stopFollowing();
    redraw();
    // Draw again once the ticket's fonts have loaded (the first drawing may use fallback fonts)
    if (document.fonts && document.fonts.load) {
      Promise.all([document.fonts.load(font(400, 26), 'A'), document.fonts.load(font(700, 26), 'A')])
        .then(redraw, function() {});
    }
    var $dialog = dialog();
    $dialog.find('#qbo-ticket-form').on('submit', function(event) {
      event.preventDefault();
      send();
    });
    $('#ajax-modal').off('dialogclose.qboTickets').on('dialogclose.qboTickets', stopFollowing);
  }

  function showErrors(messages) {
    var $errors = dialog().find('.qbo-ticket-errors');
    $errors.empty().prop('hidden', !messages.length);
    if (messages.length) {
      var $list = $('<ul>');
      messages.forEach(function(message) { $list.append($('<li>').text(message)); });
      $errors.append($('<div id="errorExplanation">').append($list));
    }
  }

  function send() {
    var $dialog = dialog();
    var $submit = $dialog.find('.qbo-ticket-submit').prop('disabled', true);
    showErrors([]);
    redraw(); // the printing time is now
    $.ajax({
      url: $dialog.data('create-url'),
      method: 'POST',
      dataType: 'json',
      headers: { 'X-CSRF-Token': $('meta[name="csrf-token"]').attr('content') },
      data: {
        appointment_id: $dialog.data('appointment-id'),
        image: preview().toDataURL('image/png'),
        copies: $dialog.find('#qbo_ticket_copies').val(),
        printer_id: $dialog.find('#qbo_ticket_printer').val()
      }
    }).done(function(job) {
      follow(job);
    }).fail(function(xhr) {
      var errors = (xhr.responseJSON && xhr.responseJSON.errors) || [$dialog.data('text-failed')];
      showErrors(errors);
      $submit.prop('disabled', false);
    });
  }

  function setStatus(text, state) {
    var $status = dialog().find('.qbo-ticket-status');
    $status.prop('hidden', false).attr('data-state', state || 'working');
    $status.find('.qbo-ticket-status-text').text(text);
    $status.find('.qbo-ticket-again').toggle(state === 'printed' || state === 'failed');
  }

  function stopFollowing() {
    if (pollTimer) { clearTimeout(pollTimer); }
    pollTimer = null;
    following = null;
  }

  // Follows the print job until it's printed, failed or expired
  function follow(job) {
    var $dialog = dialog();
    stopFollowing();
    following = { url: job.url, errors: 0 };
    // .hide(): Redmine's styles show forms whatever their hidden attribute says
    $dialog.find('#qbo-ticket-form').hide();
    setStatus(job.printer_online ? $dialog.data('text-printing') : $dialog.data('text-offline'));
    poll(following);
  }

  function poll(state) {
    if (following !== state) { return; }
    $.ajax({ url: state.url, dataType: 'json', cache: false }).done(function(data) {
      if (following !== state) { return; }
      state.errors = 0;
      if (data.finished) {
        setStatus(data.status_label + (data.error ? ': ' + data.error : ''),
                  data.status === 'printed' ? 'printed' : 'failed');
        stopFollowing();
        return;
      }
      var $dialog = dialog();
      if (data.status === 'printing') {
        setStatus($dialog.data('text-printing'));
      } else {
        setStatus(data.printer_online ? $dialog.data('text-waiting') : $dialog.data('text-offline'));
      }
      pollTimer = setTimeout(function() { poll(state); }, 1000);
    }).fail(function() {
      if (following !== state) { return; }
      state.errors += 1;
      if (state.errors >= 5) {
        setStatus(dialog().data('text-lost'), 'failed');
        stopFollowing();
      } else {
        pollTimer = setTimeout(function() { poll(state); }, 2000);
      }
    });
  }

  // Back to the form, to print it again
  function again() {
    var $dialog = dialog();
    stopFollowing();
    $dialog.find('.qbo-ticket-status').prop('hidden', true);
    $dialog.find('#qbo-ticket-form').show().find('.qbo-ticket-submit').prop('disabled', false);
    redraw();
  }

  return { initDialog: initDialog, again: again, render: render, WIDTH: WIDTH };
})(jQuery);
