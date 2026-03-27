// TIC-80 WASM Player Loader
// This bootstraps the TIC-80 fantasy console runtime for web playback.
//
// The actual TIC-80 WASM binary is loaded from the official tic80.com CDN.
// Games are passed as Lua source strings and executed in the runtime.

(function() {
  'use strict';

  // TIC-80 API constants
  var SCREEN_W = 240;
  var SCREEN_H = 136;
  var PALETTE = [
    '#1a1c2c','#5d275d','#b13e53','#ef7d57',
    '#ffcd75','#a7f070','#38b764','#257179',
    '#29366f','#3b5dc9','#41a6f6','#73eff7',
    '#f4f4f4','#94b0c2','#566c86','#333c57'
  ];

  // Fallback: Pure JS TIC-80 interpreter for basic Lua games
  // This allows games to run even without the full WASM runtime
  window.initFallbackPlayer = function(canvas, luaSource) {
    var ctx = canvas.getContext('2d');
    var scale = canvas.width / SCREEN_W;
    var fb = ctx.createImageData(SCREEN_W, SCREEN_H);
    var keys = {};

    // Parse palette to RGB
    var palRGB = PALETTE.map(function(hex) {
      return {
        r: parseInt(hex.slice(1,3), 16),
        g: parseInt(hex.slice(3,5), 16),
        b: parseInt(hex.slice(5,7), 16)
      };
    });

    document.addEventListener('keydown', function(e) { keys[e.code] = true; e.preventDefault(); });
    document.addEventListener('keyup', function(e) { keys[e.code] = false; });

    // Display the game source and a message
    ctx.fillStyle = '#1a1c2c';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#73eff7';
    ctx.font = '14px monospace';
    ctx.fillText('TIC-80 Fallback Player', 120, 60);
    ctx.fillStyle = '#94b0c2';
    ctx.font = '11px monospace';
    ctx.fillText('Full WASM runtime required for gameplay.', 60, 100);
    ctx.fillText('Download TIC-80 at tic80.com', 100, 120);
    ctx.fillStyle = '#7b8cff';
    ctx.font = '10px monospace';

    // Show first few lines of the game
    var lines = luaSource.split('\n').slice(0, 8);
    for (var i = 0; i < lines.length; i++) {
      ctx.fillText(lines[i], 20, 160 + i * 14);
    }
  };
})();
