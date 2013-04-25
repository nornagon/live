document.head.appendChild(document.createElement 'style').textContent = '''
canvas { border: 1px solid black; position: fixed }
.CodeMirror { -webkit-flex: 1; margin-left: 1em; height: 100%; }
'''
div = document.body.appendChild document.createElement 'div'
div.style[k] = v for k,v of {
  display: '-webkit-flex'
  webkitFlexFlow: 'row'
}
canvasDiv = div.appendChild document.createElement 'div'
canvasDiv.style[k] = v for k,v of {
  width: '500px'
  height: '500px'
}
canvas = canvasDiv.appendChild document.createElement 'canvas'
canvas.width = canvas.height = 500
iframe = document.body.appendChild document.createElement 'iframe'
iframe.style.display = 'none'

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
      tok.onmousedown = (e) ->
        initial_x = e.pageX
        cm.setOption 'readOnly', 'nocursor'
        cm.scrubbing = true

        originalValue = Number(tok.textContent)
        delta = deltaForNumber originalValue
        cm.doc.setSelection({line,ch:begin}, {line,ch:end})
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
        window.onmousemove = (e) ->
          d = Number((Math.round((e.pageX - initial_x)/2)*delta + originalValue).toFixed(5))
          if changed
            cm.doc.undo()
          cm.doc.replaceSelection(''+d)
          changed = true
          iframe.contentWindow.$values[m.value_id] = d
          e.stopPropagation()
          e.preventDefault()
        window.onmouseup = window.blur = ->
          window.onmousemove = undefined
          overlay.remove()
          cm.setOption 'readOnly', false
          cm.focus()
          cm.scrubbing = false
      tok.style.borderBottom = '1px dashed blue'
      tok.style.cursor = 'ew-resize'
  return

preamble = '''
var mouse = {x:0, y:0};

(function () {

var listeners = {}
window.on = function on(ev, fn) {
  var ref;
  (ref = listeners[ev] ? ref : listeners[ev] = []).push(fn);
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
var beginTime = performance.now();
webkitRequestAnimationFrame(function again(t) {
  webkitRequestAnimationFrame(again);
  var dt = (t-beginTime)/1000;
  beginTime = t;
  if (running)
    emit('frame', dt);
});
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
    m.clear() for m in cm.getAllMarks()
    xfmd = xform cm.doc.getValue()
    for i,val of xfmd.values
      m = cm.markText {line:val.loc.start.line-1,ch:val.loc.start.column}, {line:val.loc.end.line-1, ch:val.loc.end.column}, {
        className: 'token'
        inclusiveLeft: true
        inclusiveRight: true
      }
      m.value_id = i
    ast_json = JSON.stringify xfmd.ast, (k,v) -> if k is 'loc' then undefined else v
    values_json = JSON.stringify xfmd.values, (k,v) -> if k is 'loc' then v.start else v
    # TODO: if just a value changed, update it realtime.
    if ast_json == old_ast_json and values_json == old_values_json
      return
    old_values_json = values_json
    old_ast_json = ast_json
    newIframe = document.createElement 'iframe'
    iframe.parentNode.replaceChild newIframe, iframe
    iframe = newIframe
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
              {
                type: 'Property'
                key:
                  type: 'Literal'
                  value: k
                value:
                  type: 'Literal'
                  value: v.value
                kind: 'init'
              } for k, v of xfmd.values
            )
        ]
      ]) + escodegen.generate xfmd.ast
    iframe.contentDocument.body.appendChild s
  catch e
    console.error e.stack
  return

window.onblur = -> iframe.contentWindow.pause()
window.onfocus = -> iframe.contentWindow.play()

needsUpdate = false
setNeedsUpdate = ->
  return if needsUpdate
  needsUpdate = true
  setTimeout ->
    updateIframe()
    needsUpdate = false
  , 200

cm.on 'change', (cm, change) ->
  if cm.scrubbing
    return
  else
    setNeedsUpdate()

cm.doc.setValue '''
ctx = canvas.getContext('2d')
t = 0
on('frame', function frame(dt) {
  t += dt*1000
  ctx.clearRect(0, 0, canvas.width, canvas.height)
  ctx.fillStyle = 'red'
  h = 48.9
  r = 7
  ctx.fillRect(mouse.x+Math.sin(t/h)*r-6,
               mouse.y+Math.cos(t/h)*r-6,
               12, 12)
})
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
