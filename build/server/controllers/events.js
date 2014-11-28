// Generated by CoffeeScript 1.8.0
var Event, MailHandler, User, VCalendar, log, mails, moment;

moment = require('moment-timezone');

log = require('printit')({
  prefix: 'events'
});

User = require('../models/user');

Event = require('../models/event');

VCalendar = require('cozy-ical').VCalendar;

MailHandler = require('../mails/mail_handler');

mails = new MailHandler();

module.exports.fetch = function(req, res, next, id) {
  return Event.find(id, function(err, event) {
    var acceptLanguage;
    if (err || !event) {
      acceptLanguage = req.headers['accept-language'];
      if ((acceptLanguage != null ? acceptLanguage.indexOf('text/html') : void 0) !== -1) {
        return res.send({
          error: "Event not found"
        }, 404);
      } else {
        return res.send("Event not found: the event is probably canceled.", 404);
      }
    } else {
      req.event = event;
      return next();
    }
  });
};

module.exports.all = function(req, res) {
  return Event.all(function(err, events) {
    if (err) {
      return res.send({
        error: 'Server error occurred while retrieving data'
      });
    } else {
      return res.send(events);
    }
  });
};

module.exports.read = function(req, res) {
  return res.send(req.event);
};

module.exports.create = function(req, res) {
  var data;
  data = req.body;
  data.created = moment().tz('UTC').toISOString();
  data.lastModification = moment().tz('UTC').toISOString();
  return Event.createOrGetIfImport(data, function(err, event) {
    if (err) {
      return res.error("Server error while creating event.");
    }
    return res.send(event, 201);
  });
};

module.exports.update = function(req, res) {
  var data, start;
  start = req.event.start;
  data = req.body;
  data.lastModification = moment().tz('UTC').toISOString();
  return req.event.updateAttributes(data, function(err, event) {
    var dateChanged;
    if (err != null) {
      return res.send({
        error: "Server error while saving event"
      }, 500);
    } else {
      dateChanged = data.start !== start;
      return mails.sendInvitations(event, dateChanged, function(err, event2) {
        return res.send(event2 || event, 200);
      });
    }
  });
};

module.exports["delete"] = function(req, res) {
  return req.event.destroy(function(err) {
    if (err != null) {
      return res.send({
        error: "Server error while deleting the event"
      }, 500);
    } else {
      return mails.sendDeleteNotification(req.event, function() {
        return res.send({
          success: true
        }, 200);
      });
    }
  });
};

module.exports["public"] = function(req, res) {
  var date, dateFormat, key, visitor, _ref;
  key = req.query.key;
  if (!(visitor = req.event.getGuest(key))) {
    return res.send({
      error: 'invalid key'
    }, 401);
  }
  if ((_ref = req.query.status) === 'ACCEPTED' || _ref === 'DECLINED') {
    return visitor.setStatus(req.query.status, function(err) {
      if (err) {
        return res.send({
          error: "server error occured"
        }, 500);
      }
      res.header({
        'Location': "./" + req.event.id + "?key=" + key
      });
      return res.send(303);
    });
  } else {
    dateFormat = 'MMMM Do YYYY, h:mm a';
    date = moment(req.event.start).format(dateFormat);
    return res.render('event_public.jade', {
      event: req.event,
      date: date,
      key: key,
      visitor: visitor
    });
  }
};

module.exports.ical = function(req, res) {
  var calendar, key;
  key = req.query.key;
  calendar = new VCalendar({
    organization: 'Cozy Cloud',
    title: 'Cozy Agenda'
  });
  calendar.add(req.event.toIcal());
  res.header({
    'Content-Type': 'text/calendar'
  });
  return res.send(calendar.toString());
};

module.exports.publicIcal = function(req, res) {
  var calendar, key, visitor;
  key = req.query.key;
  if (!(visitor = req.event.getGuest(key))) {
    return res.send({
      error: 'invalid key'
    }, 401);
  }
  calendar = new VCalendar('Cozy Cloud', 'Cozy Agenda');
  calendar.add(req.event.toIcal());
  res.header({
    'Content-Type': 'text/calendar'
  });
  return res.send(calendar.toString());
};

module.exports.bulkCalendarRename = function(req, res) {
  var newName, oldName, _ref;
  _ref = req.body, oldName = _ref.oldName, newName = _ref.newName;
  if (oldName == null) {
    return res.send(400, {
      error: '`oldName` is mandatory'
    });
  } else if (newName == null) {
    return res.send(400, {
      error: '`newName` is mandatory'
    });
  } else {
    return Event.bulkCalendarRename(oldName, newName, function(err, events) {
      if (err != null) {
        return res.send(500, {
          error: err
        });
      } else {
        return res.send(200, events);
      }
    });
  }
};

module.exports.bulkDelete = function(req, res) {
  var calendarName;
  calendarName = req.body.calendarName;
  if (calendarName == null) {
    return res.send(400, {
      error: '`calendarName` is mandatory'
    });
  } else {
    return Event.bulkDelete(calendarName, function(err, events) {
      if (err != null) {
        return res.send(500, {
          error: err
        });
      } else {
        return res.send(200, events);
      }
    });
  }
};