xform = (code, prefix='') ->
  parsed = esprima.parse code, loc: true

  $values = {}
  nextId = 1
  replace = (e) ->
    if e.type is 'Literal' and typeof e.value is 'number'
      id = nextId++
      $values[prefix+id] = {value: e.value, loc: e.loc}
      type: "MemberExpression"
      computed: true
      object:
        type: 'Identifier'
        name: '$values'
      property:
        type: 'Literal'
        value: prefix+''+id
    else if e.type is 'UnaryExpression' and e.operator is '-' and e.argument.type is 'Literal' and typeof e.argument.value is 'number'
      id = nextId++
      $values[prefix+id] = {value: -e.argument.value, loc: e.loc}
      type: "MemberExpression"
      computed: true
      object:
        type: 'Identifier'
        name: '$values'
      property:
        type: 'Literal'
        value: prefix+''+id
    else
      transform e, replace

  # calls |f| on each node in the AST |object|
  transform = (object, f) ->
    if object instanceof Array
      newObject = []
      for v,i in object
        if typeof v is 'object' && v isnt null
          newObject[i] = f(v)
        else
          newObject[i] = v
    else
      newObject = {}
      for own key, value of object
        if typeof value is 'object' && value isnt null
          newObject[key] = f(value)
        else
          newObject[key] = value
    newObject

  xformed = transform parsed, replace
  { ast: xformed, values: $values }

window.xform = xform
