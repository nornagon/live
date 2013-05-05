document.head.appendChild(document.createElement 'style').textContent = '''
.main > canvas { border: 1px solid black; position: fixed }
.CodeMirror { -webkit-flex: 1; margin-left: 1em; height: 100%; }
'''
div = document.body.appendChild document.createElement 'div'
div.style[k] = v for k,v of {
  display: '-webkit-flex'
  webkitFlexFlow: 'row'
}
canvasDiv = div.appendChild document.createElement 'div'
canvasDiv.className = 'main'
canvasDiv.style[k] = v for k,v of {
  width: '500px'
  height: '500px'
}
canvas = canvasDiv.appendChild document.createElement 'canvas'
canvas.width = canvas.height = 500
iframe = document.body.appendChild document.createElement 'iframe'
iframe.style.display = 'none'

xfmd_values = null

cm = CodeMirror div, flattenSpans: no, lineWrapping: yes
cm.on 'renderLine', (cm, line, el) ->
  nums = el.querySelectorAll '.token'
  line = cm.getLineNumber(line)
  for tok in nums
    do (tok) ->
      begin = 0
      pr = tok
      begin += pr.textContent.length while pr = pr.previousSibling
      end = begin + tok.textContent.length
      m = cm.findMarksAt({line,ch:begin})[0]
      return unless m
      tok.style.borderBottom = '1px dashed blue'
      is_num = typeof xfmd_values[m.value_id].value is 'number'
      if is_num
        tok.style.cursor = 'ew-resize'
        tok.onmousedown = (e) ->
          initial_x = e.pageX
          cm.setOption 'readOnly', 'nocursor'
          cm.scrubbing = true
          cm.doc.setSelection({line,ch:begin}, {line,ch:end})

          originalValue = Number(tok.textContent)
          delta = deltaForNumber originalValue
          e.stopPropagation()
          e.preventDefault()
          overlay = document.createElement('div')
          overlay.style[k] = v for k,v of {
            position: 'absolute'
            left: 0, top: 0, width: '100%', height: '100%'
            cursor: 'ew-resize'
            zIndex: 10000
          }
          document.body.appendChild overlay
          changed = false
          window.addEventListener 'mousemove', move = (e) ->
            d = Number((Math.round((e.pageX - initial_x)/2)*delta + originalValue).toFixed(5))
            if changed
              cm.doc.undo()
            cm.doc.replaceSelection(''+d)
            changed = true
            iframe.contentWindow.$values[m.value_id] = d
            e.stopPropagation()
            e.preventDefault()
          up = ->
            window.removeEventListener 'mousemove', move
            window.removeEventListener 'mouseup', up
            window.removeEventListener 'blur', up
            overlay.remove()
            cm.setOption 'readOnly', false
            cm.focus()
            cm.scrubbing = false
            window.localStorage['code'] = cm.doc.getValue()
          window.addEventListener 'mouseup', up
          window.addEventListener 'blur', up
      else
        tok.style.cursor = 'pointer'
        tok.onclick = (e) ->
          cm.setOption 'readOnly', 'nocursor'
          cm.scrubbing = true
          cm.doc.setSelection({line,ch:begin}, {line,ch:end})

          quote = tok.textContent[0]
          p = new thistle.Picker tok.textContent.substr(1, tok.textContent.length-2)

          changed = false
          p.on 'changed', ->
            if changed
              cm.doc.undo()
            color = p.getCSS()
            cm.doc.replaceSelection quote + color + quote
            changed = true
            iframe.contentWindow.$values[m.value_id] = color
          p.on 'closed', ->
            cm.setOption 'readOnly', false
            cm.focus()
            cm.scrubbing = false
            window.localStorage['code'] = cm.doc.getValue()

          p.presentModalBeneath tok
  return

preamble = '''
(function () {

var listeners = {}
window.on = function on(ev, fn) {
  var ref = listeners[ev];
  (ref ? ref : listeners[ev] = []).push(fn);
}
function emit(ev) {
  var fs = listeners[ev], args = Array.prototype.slice.call(arguments, 1);
  if (!fs) return;
  for (var i = 0; i < fs.length; i++) fs[i].apply(null, args);
}

canvas.addEventListener('mousemove', function(e) {
  mouse.x = e.offsetX;
  mouse.y = e.offsetY;
  emit('mousemove', mouse)
});
canvas.addEventListener('mousedown', function(e) {
  emit('mousedown', {x:e.offsetX,y:e.offsetY})
});
canvas.addEventListener('mouseup', function(e) {
  emit('mouseup', {x:e.offsetX,y:e.offsetY})
});
canvas.addEventListener('click', function(e) {
  emit('click', {x:e.offsetX,y:e.offsetY})
});

var running = true;
var focused = true;
var beginTime = performance.now();
webkitRequestAnimationFrame(function again(t) {
  webkitRequestAnimationFrame(again);
  var dt = (t-beginTime)/1000;
  if (dt > 0.1) dt = 0.1;
  beginTime = t;
  if (running && focused && !document.webkitHidden)
    emit('frame', dt);
});
window.parent.addEventListener('focus', function() {
  focused = true;
})
window.parent.addEventListener('blur', function() {
  focused = false;
})

window.pause = function pause() {
  running = false;
}
window.play = function play() {
  running = true;
}

})();
'''

old_ast_json = ''
old_values_json = ''

persistent = {}

window.cm = cm
updateIframe = ->
  try
    xfmd = xform cm.doc.getValue()
    xfmd_values = xfmd.values

    cm.operation ->
      m.clear() for m in cm.getAllMarks()
      for id,val of xfmd.values
        m = cm.markText {line:val.loc.start.line-1,ch:val.loc.start.column}, {line:val.loc.end.line-1, ch:val.loc.end.column}, {
          className: 'token'
          inclusiveLeft: true
          inclusiveRight: true
        }
        m.value_id = id

    ast_json = JSON.stringify xfmd.ast, (k,v) -> if k is 'loc' then undefined else v
    values_json = JSON.stringify xfmd.values, (k,v) -> if k is 'loc' then v.start else v
    # TODO: if just a value changed as a result of this edit, update it
    # realtime.
    if ast_json == old_ast_json and values_json == old_values_json
      return
    old_values_json = values_json
    old_ast_json = ast_json
    old_mouse = iframe.contentWindow.mouse ? {x:250,y:250}
    newIframe = document.createElement 'iframe'
    iframe.parentNode.replaceChild newIframe, iframe
    iframe = newIframe
    iframe.contentWindow.mouse = old_mouse
    iframe.style.display = 'none'
    newCanvas = document.createElement('canvas')
    canvas.parentNode.replaceChild newCanvas, canvas
    canvas = newCanvas
    canvas.width = canvas.height = 500
    iframe.contentWindow.canvas = canvas
    iframe.contentWindow.persistent = persistent
    s = iframe.contentDocument.createElement 'script'
    s.textContent = preamble + escodegen.generate(
      type: 'Program'
      body: [
        type: 'VariableDeclaration'
        kind: 'var'
        declarations: [
          type: 'VariableDeclarator'
          id: { type: 'Identifier', name: '$values' }
          init:
            type: 'ObjectExpression',
            properties: (
              for k, v of xfmd.values
                {
                  type: 'Property'
                  key:
                    type: 'Literal'
                    value: k
                  value: (
                    if typeof v.value is 'string' or v.value >= 0
                      type: 'Literal'
                      value: v.value
                    else
                      type: 'UnaryExpression',
                      operator:'-',
                      argument:
                        type:'Literal',
                        value: -v.value
                  )
                  kind: 'init'
                }
            )
        ]
      ]) + escodegen.generate xfmd.ast
    iframe.contentDocument.body.appendChild s
  catch e
    cm.operation ->
      m.clear() for m in cm.getAllMarks()
    console.error e.stack
  return

needsUpdate = false
setNeedsUpdate = ->
  return if needsUpdate
  needsUpdate = true
  setTimeout ->
    window.localStorage['code'] = cm.doc.getValue()
    updateIframe()
    needsUpdate = false
  , 200

cm.on 'change', (cm, change) ->
  if cm.scrubbing
    return
  else
    setNeedsUpdate()

if sharejs?
  sharejs.open 'hello', 'text', (err, doc) ->
    doc.attach_cm cm
else
  cm.doc.setValue window.localStorage['code'] ? '''
ctx = canvas.getContext('2d')
var particles = [];

function update(dt) {
  for (var i = 0; i < particles.length; i++) {
    var p = particles[i];
    p.update(dt);
  }
  particles = cull(particles);

  particles.push(new Particle({
    x: mouse.x+rnd(0),
    y: mouse.y+rnd(0),
    vx: rnd(100),
    vy: rnd(100),
    size: linear(4+rnd(),17),
    alpha: linear(0.5, 0),
    life: 0.4,
  }));
}

function Particle(opts) {
  this.t = 0;
  this.dead = false;
  for (var k in opts) {
    if (typeof opts[k] === 'function') {
      (function(k) {
      Object.defineProperty(this, k, {
        get: function() { return opts[k](this.t/this.life); }
      })
      }).call(this, k)
    }
    this[k] = opts[k];
  }
}
Particle.prototype.update = function(dt) {
  this.t += dt;
  if (this.vx) this.x += this.vx * dt;
  if (this.vy) this.y += this.vy * dt;
  if (this.t >= this.life) this.dead = true;
}
Particle.prototype.draw = function() {
  ctx.fillStyle = 'red'
  ctx.globalAlpha = this.alpha;
  ctx.beginPath()
  ctx.arc(this.x, this.y, this.size, 0, Math.PI*2)
  ctx.fill()
}

function linear(a,b) {
  return function(t) { return a*(1-t) + b*t; }
}

function draw() {
  ctx.clearRect(0,0,canvas.width,canvas.height)
  for (var i = 0; i < particles.length; i++) {
    particles[i].draw()
  }
}

on('frame', function(dt) {
  update(dt);
  draw();
})

function rnd(x) { return (x==null?1:x)*(Math.random()*2-1); }
function cull(y) {
  var x, _i, _len, _results;
  _results = [];
  for (_i = 0, _len = y.length; _i < _len; _i++) {
    x = y[_i];
    if (!x.dead) {
      _results.push(x);
    }
  }
  return _results;
};
'''

#--------------------------------------------------------------

deltaForNumber = (n) ->
  # big ol' hax to get an approximately okay order-of-magnitude delta for
  # dragging a number around.
  # right now this has a tendency to make your number more specific all the
  # time, which might be problematic.
  return 1 if n is 0
  return 0.1 if n is 1

  lastDigit = (n) ->
    Math.round((n/10-Math.floor(n/10))*10)

  firstSig = (n) ->
    n = Math.abs(n)
    i = 0
    while lastDigit(n) is 0
      i++
      n /= 10
    i

  specificity = (n) ->
    s = 0
    loop
      abs = Math.abs(n)
      fraction = abs - Math.floor(abs)
      if fraction < 0.000001
        return s
      s++
      n = n * 10

  s = specificity n
  if s > 0
    Math.pow(10, -s)
  else
    n = Math.abs n
    Math.pow 10, Math.max 0, firstSig(n)-1
