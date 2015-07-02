#!/usr/bin/env coffee

start = (port, callback) ->
    require('americano').start
            name: 'Calendar'
            port: port
            host: process.env.HOST or "0.0.0.0"
            root: __dirname
    , (err, app, server) ->
        if err then callback err
        else app.onready = callback

if not module.parent
    port = process.env.PORT or 9113
    start port, (err) ->
        if err
            console.log "Initialization failed, not starting"
            console.log err.stack
            process.exit 1
else
    module.exports = start
