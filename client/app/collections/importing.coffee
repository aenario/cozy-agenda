ScheduleItemsCollection = require './scheduleitems'
Event = require '../models/event'
ICAL = require('ical.js')
async = require 'async'
moment = require 'moment-timezone'
SocketListener = require 'lib/socket_listener'
ALLOWEDTZ = moment.tz.names()


getSimpleProp = (comp, name) ->
    comp?.getFirstProperty(name)?.getFirstValue() or null
icalTimeToISO = (icaltime) -> icaltime?.toJSDate().toISOString()
getISODate = (comp, name) -> icalTimeToISO getSimpleProp comp, name

icaljs2cozyAttendee = (attendeeProp, index) ->
    email = attendeeProp.getFirstValue().replace 'mailto:', ''
    cozyAttendee =
        id: index + 1
        email: email
        contactid: null
        details:
            name: attendeeProp.getParameter('CN') or email
            status: attendeeProp.getParameter('PARTSTAT') or
                    'INVITATION-NOT-SENT'
    return cozyAttendee

icaljs2cozyAlarm = (alarmComponent) ->
    cozyAlarm =
        trigg: alarmComponent.getFirstProperty('TRIGG').getFirstValue('')
        tags: alarmComponent.getFirstProperty('ACTION').getFirstValue('')
    return cozyAlarm

icaljs2cozyRRule = (rrule) ->
    if rrule.until? and not rrule.until.isDate
        rrule.until.zone = ICAL.Timezone.utcTimezone
    delete rrule.tzid
    delete rrule?.bynmonthday
    delete rrule?.bynweekday
    return rrule.toString()


icaljs2cozy = (icalComponent) ->
    icalEvent = new ICAL.Event icalComponent
    # @TODO if the event has no start, we fall back to now, we should probably
    # just pop an error.
    startDate = icalEvent.startDate() or Ical.Time.now()
    timezoneStart = startDate.zone

    # @TODO if we dont know this TZ, we fall back to UTC, do we really want
    # to do this ?
    unless timezoneStart.tzid in ALLOWEDTZ
        timezoneStart = ICAL.Timezone.utcTimezone

    dtend = icalEvent.endDate
    duration = icalEvent.duration

    unless dtend or duration
        # if neither end or duration, add 1day
        endDate = icalEvent.endDate = startDate.clone().adjust(1, 0, 0, 0, 0)
        duration = icalEvent.duration

    endDate = startDate.clone().addDuration(duration)
    timezoneEnd = endDate.zone

    # @TODO if we dont know this TZ, we fall back to UTC, do we really want
    # to do this ?
    unless timezoneStart.tzid in ALLOWEDTZ
        timezoneStart = ICAL.Timezone.utcTimezone

    # Put back in the right format
    now = moment().tz('UTC').toISOString()

    event = {}
    event.uid = icalEvent.uid or uuid.v1()
    event.tags = [defaultCalendar]
    event.timezone = timezoneStart
    event.start = startDate.toString()
    event.end = endDate.toString()
    event.place = @getSimpleProp(icalComponent, 'LOCATION')
    event.details = @getSimpleProp(icalComponent, 'DESCRIPTION')
    event.description = @getSimpleProp(icalComponent, 'SUMMARY')
    event.stampDate = getISODate(icalComponent, 'DTSTAMP') or now
    event.mozLastack = @getISODate(icalComponent, 'X-MOZ-LASTACK')
    event.organizer = @getSimpleProp(icalComponent, 'ORGANIZER')
    event.categories = @getSimpleProp(icalComponent, 'CATEGORIES')
    event.created = @getISODate(icalComponent, 'CREATED')
    event.rrule = icaljs2cozyRRule(getSimpleProp(icalComponent, 'RRULE'))

    event.lastModification = getISODate(icalComponent, 'LAST-MODIFIED') or
                             getISODate(icalComponent, 'DTSTAMP') or
                             now

    event.attendees = icalComponent.getAllProperties('attendees')
                                    .map icaljs2cozyAttendee
    event.alarms = icalComponent.getAllSubcomponents('valarm')
                                    .map icaljs2cozyAlarm


    return new Event(event)




module.exports = class extends ScheduleItemsCollection

    model: Event
    url: 'events'

    constructor: (icsFile) ->
        @reader = new FileReader()
        @reader.onloadend = @onReadingDone
        @reader.readAsText icsFile
        @parseQueue = async.queue @doParseLine, 1
        @parseQueue.drain = @onParseDrain
        @transformQueue = async.queue @doTransformEvent, 1
         # create events with 3 parallels
        @createQueue = async.queue @doCreateEvent, 3
        @jcal = []
        @state = component: @jcal, stack: [@jcal]
        SocketListener.watchOne this

    onReadingProgress: (event) =>
        @trigger 'progress', event

    onReadingDone: =>
        @ics = @reader.result
        if /^BEGIN:VCALENDAR/gi.test @ics
            @trigger 'progress', 1
            ICAL.parse._eachLine @ics, (err, line) =>
                @parseQueue.push line, @onError
        else
            @onError new Error('upload wrong filetype')

    onError: (err) ->
        if err
            console.error err.message
            @trigger 'error', err

    doParseLine: (line, next) =>
        ICAL.parse._handleContentLine line, @state
        setTimeout next, 1


    doTransformEvent: (jCal, next) =>
        icalComponent = new ICAL.Component jCal
        if icalComponent.name is 'vevent'
            event = icaljs2cozy icalComponent
            @createQueue.push event, @onError
        else
            console.log "discard", jCal

        setTimeout next, 5

    doCreateEvent: (eventModel, next) ->
        eventModel.save {}, {
            ignoreMySocketNotification: true,
            success: next.bind(null, null)
            error: next
        }

    onParseDrain: =>
        calendar = @jcal[0]
        throw new Error('wrong state') unless calendar[0] is 'vcalendar'
        @calendarProperties = calendar[1]
        components = calendar[2]
        console.log("THERE", components)
        @transformQueue.push components, @onError

    onCreateDrain: =>
        SocketListener.stopWatching this
