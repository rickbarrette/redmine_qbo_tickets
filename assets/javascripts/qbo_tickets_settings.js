/*
 * The MIT License (MIT)
 *
 * Copyright (c) 2026 rick barrette
 *
 * Plugin settings (redmine_qbo_tickets): the appointment reminder's logo. The picked picture is trimmed of its
 * blank edges, sized as it will print (the paper is 576 dots across, 548 inside the margins), turned black and
 * white (or dithered, for photos), and kept as a 1-bit PNG in the settings, so the reminder prints exactly what
 * the preview shows.
 */
(function($) {
  'use strict';

  var PRINT_WIDTH = 548;   // dots inside the paper's margins
  var MAX_HEIGHT = 320;
  var MAX_LENGTH = 40000;  // the settings' limit for the data: URL (RedmineQboTickets::Settings::LOGO_MAX_LENGTH)
  var SOURCE_MAX = 2000;   // pictures are shrunk to this first, to trim them quickly

  var CRC_TABLE = (function() {
    var table = [];
    for (var n = 0; n < 256; n += 1) {
      var c = n;
      for (var k = 0; k < 8; k += 1) { c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; }
      table[n] = c >>> 0;
    }
    return table;
  })();

  function crc32(bytes) {
    var crc = 0xFFFFFFFF;
    for (var i = 0; i < bytes.length; i += 1) { crc = CRC_TABLE[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8); }
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  function uint32(value) {
    return [(value >>> 24) & 255, (value >>> 16) & 255, (value >>> 8) & 255, value & 255];
  }

  function chunk(type, data) {
    var typed = new Uint8Array(4 + data.length);
    for (var i = 0; i < 4; i += 1) { typed[i] = type.charCodeAt(i); }
    typed.set(data, 4);
    var out = new Uint8Array(12 + data.length);
    out.set(uint32(data.length), 0);
    out.set(typed, 4);
    out.set(uint32(crc32(typed)), 8 + data.length);
    return out;
  }

  // zlib-compressed bytes (the browser's CompressionStream), as a promise
  function deflate(bytes) {
    var stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream('deflate'));
    return new Response(stream).arrayBuffer().then(function(buffer) { return new Uint8Array(buffer); });
  }

  function base64(bytes) {
    var text = '';
    for (var i = 0; i < bytes.length; i += 0x8000) {
      text += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return btoa(text);
  }

  // A 1-bit grayscale PNG (as a data: URL promise) of black (true) and white pixels
  function encodePng(black, width, height) {
    var rowBytes = Math.ceil(width / 8);
    var raw = new Uint8Array((rowBytes + 1) * height);
    for (var y = 0; y < height; y += 1) {
      var row = y * (rowBytes + 1);
      for (var x = 0; x < width; x += 1) {
        if (!black[y * width + x]) { raw[row + 1 + (x >> 3)] |= 0x80 >> (x & 7); }
      }
      for (var pad = width; pad < rowBytes * 8; pad += 1) { raw[row + 1 + (pad >> 3)] |= 0x80 >> (pad & 7); }
    }
    return deflate(raw).then(function(compressed) {
      var header = new Uint8Array(13);
      header.set(uint32(width), 0);
      header.set(uint32(height), 4);
      header.set([1, 0, 0, 0, 0], 8);
      var parts = [new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', header),
                   chunk('IDAT', compressed), chunk('IEND', new Uint8Array(0))];
      var length = parts.reduce(function(sum, part) { return sum + part.length; }, 0);
      var png = new Uint8Array(length), offset = 0;
      parts.forEach(function(part) { png.set(part, offset); offset += part.length; });
      return 'data:image/png;base64,' + base64(png);
    });
  }

  // The picture on white (for transparent logos), at most SOURCE_MAX across, trimmed of its blank edges
  function trimmed(image) {
    var scale = Math.min(1, SOURCE_MAX / Math.max(image.naturalWidth, image.naturalHeight));
    var w = Math.max(1, Math.round(image.naturalWidth * scale)), h = Math.max(1, Math.round(image.naturalHeight * scale));
    var canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    var ctx = canvas.getContext('2d');
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, w, h);
    ctx.drawImage(image, 0, 0, w, h);
    var px = ctx.getImageData(0, 0, w, h).data;
    var left = w, top = h, right = -1, bottom = -1;
    for (var y = 0; y < h; y += 1) {
      for (var x = 0; x < w; x += 1) {
        var i = (y * w + x) * 4;
        if (px[i] < 245 || px[i + 1] < 245 || px[i + 2] < 245) {
          if (x < left) { left = x; }
          if (x > right) { right = x; }
          if (y < top) { top = y; }
          if (y > bottom) { bottom = y; }
        }
      }
    }
    if (right < 0) { return { canvas: canvas, x: 0, y: 0, w: w, h: h }; }
    return { canvas: canvas, x: left, y: top, w: right - left + 1, h: bottom - top + 1 };
  }

  // Black and white pixels of the trimmed picture at percent of the print width: darker than level is black
  // (or, dithered, spread as dots)
  function bitmap(source, percent, level, dither) {
    var width = Math.max(1, Math.round(PRINT_WIDTH * percent / 100));
    var height = Math.max(1, Math.round(source.h * width / source.w));
    if (height > MAX_HEIGHT) {
      width = Math.max(1, Math.round(width * MAX_HEIGHT / height));
      height = MAX_HEIGHT;
    }
    var canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    var ctx = canvas.getContext('2d');
    ctx.imageSmoothingQuality = 'high';
    ctx.drawImage(source.canvas, source.x, source.y, source.w, source.h, 0, 0, width, height);
    var px = ctx.getImageData(0, 0, width, height).data;
    var gray = new Float32Array(width * height);
    for (var i = 0; i < gray.length; i += 1) {
      gray[i] = 0.299 * px[i * 4] + 0.587 * px[i * 4 + 1] + 0.114 * px[i * 4 + 2];
    }
    var black = new Uint8Array(width * height);
    for (var y = 0; y < height; y += 1) {
      for (var x = 0; x < width; x += 1) {
        var at = y * width + x, old = gray[at];
        black[at] = old < level ? 1 : 0;
        if (!dither) { continue; }
        // Floyd-Steinberg: the error goes to the pixels not yet done
        var error = old - (black[at] ? 0 : 255);
        if (x + 1 < width) { gray[at + 1] += error * 7 / 16; }
        if (y + 1 < height) {
          if (x > 0) { gray[at + width - 1] += error * 3 / 16; }
          gray[at + width] += error * 5 / 16;
          if (x + 1 < width) { gray[at + width + 1] += error / 16; }
        }
      }
    }
    return { black: black, width: width, height: height };
  }

  function init() {
    var $box = $('#qbo-tickets-logo');
    if (!$box.length) { return; }
    var $value = $box.find('input.qbo-tickets-logo-value');
    var $preview = $box.find('img.qbo-tickets-logo-preview');
    var $info = $box.find('.qbo-tickets-logo-info');
    var $controls = $box.find('.qbo-tickets-logo-controls');
    var $error = $box.find('.qbo-tickets-logo-error');
    var source = null, pending = 0;

    function show(url) {
      $value.val(url || '');
      $preview.prop('hidden', !url);
      $box.find('.qbo-tickets-logo-paper').prop('hidden', !url);
      $box.find('.qbo-tickets-logo-remove').prop('hidden', !url);
      if (!url) { $info.text(''); return; }
      $preview.attr('src', url).one('load', function() {
        // The preview's paper is half size: 576 dots across as 288px
        $preview.css('width', (this.naturalWidth / 2) + 'px');
        $info.text($box.data('text-size').replace('%{width}', this.naturalWidth)
          .replace('%{height}', this.naturalHeight).replace('%{kb}', Math.ceil(url.length / 1024)));
      });
    }

    function update() {
      if (!source) { return; }
      var run = ++pending;
      var bits = bitmap(source, Number($box.find('.qbo-tickets-logo-width').val()),
                        Number($box.find('.qbo-tickets-logo-level').val()),
                        $box.find('.qbo-tickets-logo-dither').prop('checked'));
      encodePng(bits.black, bits.width, bits.height).then(function(url) {
        if (run !== pending) { return; }
        if (url.length > MAX_LENGTH) {
          $error.text($box.data('text-too-big')).prop('hidden', false);
          return;
        }
        $error.prop('hidden', true);
        show(url);
      });
    }

    $box.find('.qbo-tickets-logo-file').on('change', function() {
      var file = this.files && this.files[0];
      if (!file) { return; }
      if (!window.CompressionStream) {
        $error.text($box.data('text-unsupported')).prop('hidden', false);
        return;
      }
      var image = new Image(), url = URL.createObjectURL(file);
      image.onload = function() {
        URL.revokeObjectURL(url);
        source = trimmed(image);
        $controls.prop('hidden', false);
        update();
      };
      image.onerror = function() {
        URL.revokeObjectURL(url);
        $error.text($box.data('text-unreadable')).prop('hidden', false);
      };
      image.src = url;
    });
    $box.find('.qbo-tickets-logo-width, .qbo-tickets-logo-level').on('input', update);
    $box.find('.qbo-tickets-logo-dither').on('change', update);
    $box.find('.qbo-tickets-logo-remove').on('click', function(event) {
      event.preventDefault();
      source = null;
      pending += 1;
      $box.find('.qbo-tickets-logo-file').val('');
      $controls.prop('hidden', true);
      show('');
    });

    show($value.val());
  }

  $(init);
})(jQuery);
