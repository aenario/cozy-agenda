fs = require 'fs'
Polyglot = require 'node-polyglot'
cozydb = require 'cozydb'

# Seeks the proper locale files, depending if we run from build/ or from sources
path = require 'path'
LOCALE_PATH = path.resolve __dirname, '../../client/app/locales/'

class LocalizationManager

    polyglot: null
    templateCache: {}

    # should be run when app starts
    initialize: (locale, renderer, callback = () ->) ->
        locale ?= 'en' # default value

        try
            phrases = require "#{LOCALE_PATH}/#{locale}"
        catch err
            phrases = require "#{LOCALE_PATH}/en"

        @polyglot = new Polyglot {locale, phrases}
        callback null, @polyglot

    # execute polyglot.t, for server-side localization
    t: (key, params = {}) -> return @polyglot?.t key, params

    setRenderer: (renderer) ->
        @renderer = renderer

    getViewName: (name) ->
        "#{@polyglot.currentLocale}/#{name}"

    getDateFormat: (event) ->
        if event.isAllDayEvent()
            dateFormatKey = 'email date format allday'
        else
            dateFormatKey = 'email date format'
        return @t dateFormatKey

    render: (name, params, callback) ->
        name = getViewName name
        @renderer name, params, callback

    # for template localization
    getPolyglot: -> return @polyglot

module.exports = new LocalizationManager()
