// Copyright: Kartei contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html
//
// Card page support shared by the Apple and Android apps:
//  - replay buttons for [sound:] and TTS tags (posts "play:q:0" style messages to the app),
//  - a self-contained renderer for Anki 23.10+ image occlusion notes, written for Kartei.
//
// Image occlusion data format (from Anki's rslib/src/cloze.rs and image_occlusion/imageocclusion.rs):
// each occlusion renders as <div class="cloze|cloze-inactive|cloze-highlight" data-ordinal="1"
// data-shape="rect|ellipse|polygon|text" data-left=".1" data-top=".2" data-width=".3" data-height=".1"
// data-rx data-ry data-points="x,y x,y" data-angle data-fill data-occludeinactive="1" data-text data-scale
// data-font-size>. Coordinates are 0-1 fractions of the image. "cloze" is the asked shape on the question
// side (and any ordinal-0 shape), "cloze-inactive" the other shapes, "cloze-highlight" the asked shape on the
// answer side. Inactive shapes are only drawn when occludeInactive is 1 ("hide all, guess one").

(function () {
  "use strict";

  var kartei = (window.kartei = window.kartei || {});

  /** Send a message to the app: WKScriptMessageHandler on Apple, a JavascriptInterface on Android. */
  kartei.post = function (message) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.kartei) {
        window.webkit.messageHandlers.kartei.postMessage(message);
      } else if (window.KarteiBridge && window.KarteiBridge.post) {
        window.KarteiBridge.post(message);
      }
    } catch (e) {}
  };

  kartei.play = function (ref) { kartei.post("play:" + ref); return false; };

  // ---- Image occlusion -------------------------------------------------------------------------

  var MASK = "#ffeba2"; // Anki's SHAPE_MASK_COLOR
  var TEXT_BG = "#ffffff", TEXT_FONT = "Arial", TEXT_PAD = 5, TEXT_SIZE = 40;
  var ANGLE_STEPS = 10000;

  function num(v, fallback) {
    var n = parseFloat(v);
    return isNaN(n) ? fallback : n;
  }

  /** Stored angle (1/10000 of a turn) to degrees, as Anki's storedToAngle. */
  function storedToAngle(x) {
    var steps = Number(x) % ANGLE_STEPS;
    return isNaN(steps) ? 0 : (steps / ANGLE_STEPS) * 360;
  }

  /** Read one rendered occlusion div into a plain shape object (normalised 0-1 coordinates). */
  function shapeFrom(el) {
    var d = el.dataset;
    var type = d.shape;
    if (type !== "rect" && type !== "ellipse" && type !== "polygon" && type !== "text") return null;
    var s = {
      type: type,
      ordinal: parseInt(d.ordinal, 10),
      occludeInactive: d.occludeinactive === "1",
      left: num(d.left, 0),
      top: num(d.top, 0),
      angle: storedToAngle(d.angle),
      fill: d.fill == null ? MASK : d.fill,
    };
    if (type === "rect") { s.width = num(d.width, 0); s.height = num(d.height, 0); }
    if (type === "ellipse") { s.rx = num(d.rx, 0); s.ry = num(d.ry, 0); }
    if (type === "polygon") {
      s.points = (d.points || "").split(" ").filter(Boolean).map(function (p) {
        var xy = p.split(",");
        return { x: num(xy[0], 0), y: num(xy[1], 0) };
      });
      if (!s.points.length) s.points = [{ x: 0, y: 0 }];
    }
    if (type === "text") {
      s.text = d.text || "";
      s.scale = num(d.scale, 1);
      s.fontSize = d.fontSize ? num(d.fontSize, 0) : 0;
    }
    return s;
  }

  function shapes(selector) {
    return Array.prototype.slice.call(document.querySelectorAll(selector))
      .filter(function (el) { return el.tagName === "DIV"; })
      .map(shapeFrom)
      .filter(Boolean);
  }

  /** Anki rounds fractions to whole canvas pixels (position.ts xFromNormalized). */
  function px(f, size) { return Math.round(f * size); }

  function drawShape(ctx, W, H, s, fill, stroke, strokeWidth) {
    ctx.fillStyle = fill;
    ctx.strokeStyle = stroke;
    ctx.lineWidth = strokeWidth;
    var left = px(s.left, W), top = px(s.top, H);
    var angle = (s.angle || 0) * Math.PI / 180;
    if (s.type === "rect" || s.type === "ellipse") {
      if (angle) { ctx.save(); ctx.translate(left, top); ctx.rotate(angle); ctx.translate(-left, -top); }
      if (s.type === "rect") {
        var w = px(s.width, W), h = px(s.height, H);
        ctx.fillRect(left, top, w, h);
        if (strokeWidth) ctx.strokeRect(left, top, w, h);
      } else {
        var rx = px(s.rx, W), ry = px(s.ry, H);
        ctx.beginPath();
        ctx.ellipse(left + rx, top + ry, rx, ry, 0, 0, Math.PI * 2, false);
        ctx.closePath();
        ctx.fill();
        if (strokeWidth) ctx.stroke();
      }
      if (angle) ctx.restore();
    } else if (s.type === "polygon") {
      var pts = s.points.map(function (p) { return { x: px(p.x, W), y: px(p.y, H) }; });
      var minX = pts[0].x, minY = pts[0].y;
      pts.forEach(function (p) { if (p.x < minX) minX = p.x; if (p.y < minY) minY = p.y; });
      ctx.save();
      ctx.translate(left - minX, top - minY);
      ctx.beginPath();
      ctx.moveTo(pts[0].x, pts[0].y);
      for (var i = 0; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y);
      ctx.closePath();
      ctx.fill();
      if (strokeWidth) ctx.stroke();
      ctx.restore();
    } else if (s.type === "text") {
      var size = s.fontSize ? s.fontSize * H : TEXT_SIZE;
      ctx.save();
      ctx.font = size + "px " + TEXT_FONT;
      ctx.textBaseline = "top";
      ctx.scale(s.scale, s.scale);
      var lines = s.text.split("\n");
      var m = ctx.measureText("M");
      var lineHeight = 1.5 * (m.actualBoundingBoxAscent + m.actualBoundingBoxDescent);
      var x = left / s.scale, y = top / s.scale, maxW = 0;
      lines.forEach(function (l) { maxW = Math.max(maxW, ctx.measureText(l).width); });
      if (angle) { ctx.translate(x, y); ctx.rotate(angle); ctx.translate(-x, -y); }
      ctx.fillStyle = TEXT_BG;
      ctx.fillRect(x, y, maxW + TEXT_PAD, lines.length * lineHeight + TEXT_PAD);
      ctx.fillStyle = s.fill && s.fill !== MASK ? s.fill : "#000";
      lines.forEach(function (l, i) { ctx.fillText(l, x, y + i * lineHeight); });
      ctx.restore();
    }
  }

  function border(style, name, width, colour) {
    var parts = (style.getPropertyValue(name) || "").split(" ").filter(Boolean);
    var w = parseFloat(parts[0]);
    return { width: isNaN(w) ? width : w, color: parts[1] || colour };
  }

  /** Colours from the notetype's CSS variables, with Anki's defaults. */
  function properties(canvas) {
    var st = window.getComputedStyle(canvas);
    var v = function (n, d) { var x = (st.getPropertyValue(n) || "").trim(); return x || d; };
    return {
      active: v("--active-shape-color", "#ff8e8e"),
      inactive: v("--inactive-shape-color", MASK),
      highlight: v("--highlight-shape-color", "#ff8e8e00"),
      activeBorder: border(st, "--active-shape-border", 1, "#212121"),
      inactiveBorder: border(st, "--inactive-shape-border", 1, "#212121"),
      highlightBorder: border(st, "--highlight-shape-border", 1, "#ff8e8e"),
    };
  }

  var masksHidden = false;

  /** What to draw, split out so it can be tested without a canvas. */
  function plan(onlyText) {
    var keep = function (s) { return !onlyText || s.type === "text"; };
    return {
      active: shapes(".cloze").filter(keep),
      inactive: shapes(".cloze-inactive").filter(keep).filter(function (s) { return s.occludeInactive; }),
      highlight: shapes(".cloze-highlight").filter(keep),
    };
  }

  function draw() {
    var canvas = document.getElementById("image-occlusion-canvas");
    if (!canvas) return;
    var ctx = canvas.getContext("2d");
    var W = canvas.width, H = canvas.height;
    ctx.clearRect(0, 0, W, H);
    var p = properties(canvas);
    var todo = plan(masksHidden);
    todo.active.forEach(function (s) { drawShape(ctx, W, H, s, p.active, p.activeBorder.color, p.activeBorder.width); });
    todo.inactive.forEach(function (s) {
      drawShape(ctx, W, H, s, s.fill !== MASK ? s.fill : p.inactive, p.inactiveBorder.color, p.inactiveBorder.width);
    });
    todo.highlight.forEach(function (s) { drawShape(ctx, W, H, s, p.highlight, p.highlightBorder.color, p.highlightBorder.width); });
    canvas.setAttribute("data-kartei-drawn", String(todo.active.length + todo.inactive.length + todo.highlight.length));
    describe(canvas, todo);
  }

  /** Screen readers cannot see a canvas: say what is covered. */
  function describe(canvas, todo) {
    canvas.setAttribute("role", "img");
    var asked = todo.active.length || todo.highlight.length;
    var label = todo.highlight.length
      ? "Image. The asked area is outlined."
      : "Image with " + (todo.active.length + todo.inactive.length) + " covered area" +
        (todo.active.length + todo.inactive.length === 1 ? "" : "s") + (asked ? ". Name the marked area." : ".");
    canvas.setAttribute("aria-label", label);
  }

  function sizeCanvas() {
    var canvas = document.getElementById("image-occlusion-canvas");
    var container = document.getElementById("image-occlusion-container");
    if (!canvas || !container) return false;
    var img = container.querySelector("img");
    if (!img) {
      container.textContent = "No image to show.";
      return false;
    }
    if (!img.naturalWidth) return false;
    container.style.aspectRatio = img.naturalWidth + " / " + img.naturalHeight;
    // optimumPixelSizeForCanvas: sharp on retina screens, at most 4096x4096 pixels.
    var dpr = window.devicePixelRatio || 1;
    var cw = canvas.clientWidth * dpr, ch = canvas.clientHeight * dpr;
    var scale = Math.min(cw / img.naturalWidth, ch / img.naturalHeight);
    var w = img.naturalWidth * scale, h = img.naturalHeight * scale;
    var max = 4096 * 4096;
    if (w * h > max) { var k = Math.sqrt(max) / Math.sqrt(w * h); w *= k; h *= k; }
    canvas.width = Math.max(1, Math.floor(w));
    canvas.height = Math.max(1, Math.floor(h));
    return true;
  }

  function render() {
    if (sizeCanvas()) draw();
  }

  var setupDone = false;

  function setup() {
    var container = document.getElementById("image-occlusion-container");
    if (!container) return;
    container.classList.add("k-io");
    var img = container.querySelector("img");
    // requestAnimationFrame does not fire in hidden or offscreen web views; the timer makes sure masks get drawn.
    var go = function () { window.requestAnimationFrame(render); window.setTimeout(render, 50); };
    if (img && !img.complete) {
      img.addEventListener("load", go);
      img.addEventListener("error", go);
    } else {
      go();
    }
    if (setupDone) return;
    setupDone = true;
    window.addEventListener("resize", go);
    var button = document.getElementById("toggle");
    if (button) {
      if (document.querySelector('[data-occludeinactive="1"]')) {
        button.classList.add("k-toggle");
        button.addEventListener("click", function () { masksHidden = !masksHidden; draw(); });
      } else {
        button.style.display = "none";
      }
    }
    window.addEventListener("keydown", function (e) {
      var b = document.getElementById("toggle");
      if (b && b.style.display !== "none" && e.key === "M") { masksHidden = !masksHidden; draw(); }
    });
  }

  window.anki = window.anki || {};
  window.anki.imageOcclusion = { setup: setup };
  kartei.imageOcclusion = { setup: setup, plan: plan, shapeFrom: shapeFrom, storedToAngle: storedToAngle };
})();
