/* ── Gradient Color Picker (Dark Mode) ─────────────────────
   Usage: const hex = await openColorPicker(anchorEl, '#4285f4');
   Returns hex string or null if cancelled.
────────────────────────────────────────────────────────── */

// ── HSV ↔ RGB helpers ─────────────────────────────────────
function hsvToRgb(h, s, v) {
  h = h / 360 * 6;
  const i = Math.floor(h), f = h - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  let r, g, b;
  switch (i % 6) {
    case 0: r = v; g = t; b = p; break;
    case 1: r = q; g = v; b = p; break;
    case 2: r = p; g = v; b = t; break;
    case 3: r = p; g = q; b = v; break;
    case 4: r = t; g = p; b = v; break;
    case 5: r = v; g = p; b = q; break;
  }
  return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255)];
}

function rgbToHsv(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  let h = 0, s = max === 0 ? 0 : d / max, v = max;
  if (d !== 0) {
    switch (max) {
      case r: h = ((g - b) / d + (g < b ? 6 : 0)); break;
      case g: h = ((b - r) / d + 2); break;
      case b: h = ((r - g) / d + 4); break;
    }
    h *= 60;
  }
  return [h, s, v];
}

function hexToRgb(hex) {
  hex = hex.replace('#', '');
  if (hex.length === 3) hex = hex[0]+hex[0]+hex[1]+hex[1]+hex[2]+hex[2];
  return [parseInt(hex.slice(0,2),16), parseInt(hex.slice(2,4),16), parseInt(hex.slice(4,6),16)];
}

function rgbToHex(r, g, b) {
  return '#' + [r, g, b].map(c => c.toString(16).padStart(2, '0')).join('');
}

// ── Active picker tracking ────────────────────────────────
let activePicker = null;
let activeOutsideHandler = null;

function closeActivePicker() {
  if (activePicker) {
    activePicker.remove();
    activePicker = null;
  }
  if (activeOutsideHandler) {
    document.removeEventListener('mousedown', activeOutsideHandler);
    activeOutsideHandler = null;
  }
}

// ── Main export ───────────────────────────────────────────
export function openColorPicker(anchorEl, currentColor = '#4285f4') {
  closeActivePicker();

  return new Promise((resolve) => {
    let [h, s, v] = rgbToHsv(...hexToRgb(currentColor));

    // ── Build DOM ─────────────────────────────────────────
    const picker = document.createElement('div');
    picker.className = 'gcp';
    picker.innerHTML = `
      <canvas class="gcp-sv" width="220" height="160"></canvas>
      <div class="gcp-sv-cursor"></div>
      <div class="gcp-hue-track">
        <canvas class="gcp-hue" width="220" height="14"></canvas>
        <div class="gcp-hue-thumb"></div>
      </div>
      <div class="gcp-bottom">
        <div class="gcp-preview"></div>
        <input class="gcp-hex" type="text" maxlength="7" spellcheck="false" />
      </div>
      <button class="gcp-select">Auswählen</button>
    `;

    const svCanvas = picker.querySelector('.gcp-sv');
    const svCtx = svCanvas.getContext('2d', { willReadFrequently: true });
    const svCursor = picker.querySelector('.gcp-sv-cursor');
    const hueCanvas = picker.querySelector('.gcp-hue');
    const hueCtx = hueCanvas.getContext('2d');
    const hueThumb = picker.querySelector('.gcp-hue-thumb');
    const preview = picker.querySelector('.gcp-preview');
    const hexInput = picker.querySelector('.gcp-hex');
    const selectBtn = picker.querySelector('.gcp-select');

    // ── Draw functions ────────────────────────────────────
    function drawSV() {
      const w = svCanvas.width, hh = svCanvas.height;
      // Base hue color
      const [r, g, b] = hsvToRgb(h, 1, 1);
      // Horizontal: white → hue color (saturation)
      const gradH = svCtx.createLinearGradient(0, 0, w, 0);
      gradH.addColorStop(0, '#fff');
      gradH.addColorStop(1, `rgb(${r},${g},${b})`);
      svCtx.fillStyle = gradH;
      svCtx.fillRect(0, 0, w, hh);
      // Vertical: transparent → black (value)
      const gradV = svCtx.createLinearGradient(0, 0, 0, hh);
      gradV.addColorStop(0, 'rgba(0,0,0,0)');
      gradV.addColorStop(1, '#000');
      svCtx.fillStyle = gradV;
      svCtx.fillRect(0, 0, w, hh);
    }

    function drawHue() {
      const w = hueCanvas.width, hh = hueCanvas.height;
      const grad = hueCtx.createLinearGradient(0, 0, w, 0);
      for (let i = 0; i <= 6; i++) {
        const [r, g, b] = hsvToRgb(i * 60, 1, 1);
        grad.addColorStop(i / 6, `rgb(${r},${g},${b})`);
      }
      hueCtx.fillStyle = grad;
      hueCtx.fillRect(0, 0, w, hh);
    }

    function updateUI() {
      const [r, g, b] = hsvToRgb(h, s, v);
      const hex = rgbToHex(r, g, b);
      // SV cursor position
      svCursor.style.left = (s * svCanvas.width) + 'px';
      svCursor.style.top = ((1 - v) * svCanvas.height) + 'px';
      // Hue thumb position
      hueThumb.style.left = (h / 360 * hueCanvas.width) + 'px';
      // Preview + hex
      preview.style.background = hex;
      hexInput.value = hex.toUpperCase();
    }

    // ── SV interaction ────────────────────────────────────
    function handleSV(e) {
      const rect = svCanvas.getBoundingClientRect();
      const x = Math.max(0, Math.min(e.clientX - rect.left, rect.width));
      const y = Math.max(0, Math.min(e.clientY - rect.top, rect.height));
      s = x / rect.width;
      v = 1 - y / rect.height;
      updateUI();
    }

    svCanvas.addEventListener('mousedown', (e) => {
      e.preventDefault();
      handleSV(e);
      const move = (ev) => handleSV(ev);
      const up = () => { document.removeEventListener('mousemove', move); document.removeEventListener('mouseup', up); };
      document.addEventListener('mousemove', move);
      document.addEventListener('mouseup', up);
    });

    // Touch support for SV
    svCanvas.addEventListener('touchstart', (e) => {
      e.preventDefault();
      const touch = (ev) => { const t = ev.touches[0]; handleSV(t); };
      touch(e);
      const end = () => { document.removeEventListener('touchmove', touch); document.removeEventListener('touchend', end); };
      document.addEventListener('touchmove', touch);
      document.addEventListener('touchend', end);
    });

    // ── Hue interaction ───────────────────────────────────
    function handleHue(e) {
      const rect = hueCanvas.getBoundingClientRect();
      const x = Math.max(0, Math.min(e.clientX - rect.left, rect.width));
      h = (x / rect.width) * 360;
      drawSV();
      updateUI();
    }

    const hueTrack = picker.querySelector('.gcp-hue-track');
    hueTrack.addEventListener('mousedown', (e) => {
      e.preventDefault();
      handleHue(e);
      const move = (ev) => handleHue(ev);
      const up = () => { document.removeEventListener('mousemove', move); document.removeEventListener('mouseup', up); };
      document.addEventListener('mousemove', move);
      document.addEventListener('mouseup', up);
    });

    hueTrack.addEventListener('touchstart', (e) => {
      e.preventDefault();
      const touch = (ev) => { const t = ev.touches[0]; handleHue(t); };
      touch(e);
      const end = () => { document.removeEventListener('touchmove', touch); document.removeEventListener('touchend', end); };
      document.addEventListener('touchmove', touch);
      document.addEventListener('touchend', end);
    });

    // ── Hex input ─────────────────────────────────────────
    hexInput.addEventListener('change', () => {
      let val = hexInput.value.trim();
      if (!val.startsWith('#')) val = '#' + val;
      if (/^#[0-9a-fA-F]{6}$/.test(val)) {
        [h, s, v] = rgbToHsv(...hexToRgb(val));
        drawSV();
        updateUI();
      }
    });

    // ── Select button ─────────────────────────────────────
    selectBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      const [r, g, b] = hsvToRgb(h, s, v);
      closeActivePicker();
      resolve(rgbToHex(r, g, b));
    });

    // ── Position picker ───────────────────────────────────
    document.body.appendChild(picker);
    activePicker = picker;

    const anchorRect = anchorEl.getBoundingClientRect();
    let top = anchorRect.bottom + 6;
    let left = anchorRect.left;

    // Keep in viewport
    const pRect = picker.getBoundingClientRect();
    if (left + pRect.width > window.innerWidth - 8) left = window.innerWidth - pRect.width - 8;
    if (left < 8) left = 8;
    if (top + pRect.height > window.innerHeight - 8) top = anchorRect.top - pRect.height - 6;

    picker.style.top = top + 'px';
    picker.style.left = left + 'px';

    // ── Initial draw ──────────────────────────────────────
    drawSV();
    drawHue();
    updateUI();

    // ── Close on outside click ────────────────────────────
    setTimeout(() => {
      activeOutsideHandler = (e) => {
        if (!picker.contains(e.target) && e.target !== anchorEl && !anchorEl.contains(e.target)) {
          closeActivePicker();
          resolve(null);
        }
      };
      document.addEventListener('mousedown', activeOutsideHandler);
    }, 0);
  });
}
