americano = require 'americano'
path = require 'path'
fs = require 'fs'
async = require 'async'
cozydb = require 'cozydb'

publicPath = path.resolve __dirname, '../client/public'
staticMiddleware = americano.static publicPath, maxAge: 86400000
publicStatic = (req, res, next) ->

    # Allows assets to be loaded from any route
    detectAssets = /\/(stylesheets|javascripts|images|fonts)+\/(.+)$/
    assetsMatched = detectAssets.exec req.url

    if assetsMatched?
        req.url = assetsMatched[0]

    staticMiddleware req, res, (err) -> next err

useBuildView = fs.existsSync path.resolve(__dirname, 'views/index.js')

module.exports =

    common:
        use: [
            staticMiddleware
            publicStatic
            americano.bodyParser keepExtensions: true
        ]
        useAfter: [
            americano.errorHandler
                dumpExceptions: true
                showStack: true
        ]

        afterStart: (app, server) ->
            Realtimer = require 'cozy-realtime-adapter'
            realtime = Realtimer server, ['event.*']
            locale = 'en' # default

            async.series [
                (cb) ->
                    User = require './models/user'
                    realtime.on 'user.*', -> User.updateUser()
                    User.updateUser cb
                (cb) ->
                    cozydb.api.getCozyLocale (err, cozyLocale) ->
                        locale = cozyLocale
                        cb null
                (cb) ->
                    localization = require './libs/localization_manager'
                    renderer = app.render.bind(app)
                    localization.initialize locale, renderer, ->
                        cb null
                (cb) ->
                    Event = require './models/event'
                    Event.migrateAll ->
                        cb null
                (cb) ->
                    Alarm = require './models/alarm'
                    Alarm.migrateAll ->
                        cb null
            ], (err) ->

                app.onready? err, app, server


        set:
            'view engine': if useBuildView then 'js' else 'jade'
            'views': path.resolve __dirname, 'views'

        engine:
            js: (path, locales, callback) ->
                callback null, require(path)(locales)

    development: [
        americano.logger 'dev'
    ]

    production: [
        americano.logger 'short'
    ]

    plugins: [
        'cozydb'
    ]
