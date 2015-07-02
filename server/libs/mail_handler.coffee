async = require 'async'
fs = require 'fs'
log = require('printit')
    prefix: 'MailHandler'
    date: true

Event = require '../models/event'
User = require '../models/user'
cozydb = require 'cozydb'

localization = require '../libs/localization_manager'

module.exports.sendInvitations = (event, dateChanged, callback) ->
    guests = event.toJSON().attendees
    needSaving = false

    async.parallel [
        (cb) -> cozydb.api.getCozyDomain cb
        (cb) -> User.getUserInfos cb
    ], (err, results) ->
        return callback err if err

        [domain, user] = results

        async.forEach guests, (guest, done) ->

            # only process relevant guests, quits otherwise
            shouldSend = guest.status is 'INVITATION-NOT-SENT' or \
                        (guest.status is 'ACCEPTED' and dateChanged)
            return done() unless shouldSend

            # Prepare mail
            if dateChanged
                htmlKey      = 'mail_update'
                subjectKey   = 'email update title'
                templateKey  = 'email update content'
            else
                htmlKey      = 'mail_invitation'
                subjectKey   = 'email invitation title'
                templateKey  = 'email invitation content'

            # Get mail contents
            url   = "#{domain}public/calendar/events/#{event.id}"
            date  = event.formatStart localization.getDateFormat event
            place = if event.place?.length > 0 then event.place else false

            # Build mails
            templateOptions =
                displayName:  user.name
                displayEmail: user.email
                description:  description
                place:        place
                key:          guest.key
                date:         date
                url:          url



            mailOptions =
                to:      guest.email
                subject: localization.t subjectKey, templateOptions
                content: localization.t templateKey, templateOptions

            localization.render htmlKey, templateOptions, (err, html) ->
                return done err if err
                mailOptions.html = html

                # Send mail through CozyDB API
                cozydb.api.sendMailFromUser mailOptions, (err) ->
                    if err
                        log.error "An error occured while sending invitation"
                        log.error err
                    else
                        needSaving   = true
                        guest.status = 'NEEDS-ACTION' # ical = waiting an answer

                    done err

        # Catch errors when doing async foreach
        , (err) ->
            if err?
                callback err
            else unless needSaving
                callback()
            else
                event.updateAttributes attendees: guests, callback


module.exports.sendDeleteNotification = (event, callback) ->
    guests = event.toJSON().attendees
    # only process guests that have accepted to attend the event
    guestsToInform = guests.filter (guest) ->
        return guest.status in ['ACCEPTED', 'NEEDS-ACTION']

    User.getUserInfos (err, user) ->
        return callback err if err

        async.eachSeries guestsToInform, (guest, done) ->

            date = event.formatStart localization.getDateFormat event
            place = if event.place?.length > 0 then event.place else false
            templateOptions =
                displayName: user.name
                displayEmail: user.email
                description: event.description
                place: place
                date: date
            mailOptions =
                to: guest.email
                subject: localization.t 'email delete title', templateOptions
                content: localization.t 'email delete content', templateOptions

            localization.render 'mail_delete', templateOptions, (err, html) ->
                return done err if err
                mailOptions.html = html

                cozydb.api.sendMailFromUser mailOptions, (err) ->
                    if err?
                        log.error "An error occured while sending email"
                        log.error err

                    done err

        , callback
