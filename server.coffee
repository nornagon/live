connect = require 'connect'
sharejs = require('share').server

server = connect(
  connect.logger(),
  connect.static(__dirname)
)

sharejs.attach server, db: type: 'none'

server.listen 8000
console.log 'Listening at http://localhost:8000'
