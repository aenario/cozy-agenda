// Generated by CoffeeScript 1.10.0
var User, VCalendar, _formatDate, _getDomainAndPrepareICS, _makeICSFile, _makeMailHTML, _makeTemplateOptions, _sendMail, app, async, cozydb, fs, localization, log, os, path, render;

async = require('async');

fs = require('fs');

os = require('os');

path = require('path');

log = require('printit')({
  prefix: 'MailHandler',
  date: true
});

cozydb = require('cozydb');

User = require('../models/user');

VCalendar = require('cozy-ical').VCalendar;

localization = require('cozy-localization-manager').getInstance();

app = null;

render = function(view, locales, callback) {
  if (!app) {
    throw new Error('need to call mail_handler.initialize');
  }
  return app.render(view, locales, callback);
};

module.exports.initialize = function(appref) {
  return app = appref;
};

_makeTemplateOptions = function(event, user, domain, guest) {
  var date, description, options, place, ref, url;
  ref = event.toJSON(), description = ref.description, place = ref.place;
  place = (place != null ? place.length : void 0) > 0 ? place : "";
  date = _formatDate(event);
  url = domain + "public/calendar/events/" + event.id;
  options = {
    displayName: user.name,
    displayEmail: user.email,
    description: description,
    place: place,
    key: guest.key,
    date: date,
    url: url
  };
  return options;
};

_makeMailHTML = function(template, locales, callback) {
  var locale, view;
  locale = localization.polyglot.locale();
  view = "mails/" + locale + "/" + template;
  return render(view, locales, callback);
};

_makeICSFile = function(event, user) {
  var calendar, calendarOptions, icsPath, vEvent;
  calendarOptions = {
    organization: 'Cozy Cloud',
    title: 'Cozy Calendar',
    method: 'REQUEST'
  };
  calendar = new VCalendar(calendarOptions);
  vEvent = event.toIcal();
  vEvent.model.organizer = {
    displayName: user.name,
    email: user.email
  };
  vEvent.build();
  calendar.add(vEvent);
  icsPath = path.join(os.tmpdir(), 'invite.ics');
  fs.writeFile(icsPath, calendar.toString(), function(err) {
    if (err) {
      log.error("An error occured while creating invitation file " + icsPath);
      return log.error(err);
    } else {
      return 'email date format';
    }
  });
  return icsPath;
};

_formatDate = function(event) {
  var dateFormat, dateFormatKey, locale;
  dateFormatKey = event.isAllDayEvent() ? 'email date format allday' : 'email date format';
  dateFormat = localization.t(dateFormatKey);
  locale = localization.polyglot.locale;
  return event.formatStart(dateFormat, locale);
};

_sendMail = function(guest, subject, html, content, callback) {
  var mailOptions;
  mailOptions = {
    to: guest.email,
    subject: subject,
    html: html,
    content: content,
    attachments: [
      {
        path: path.resolve(__dirname, '../assets/cozy-logo.png'),
        filename: 'cozy-logo.png',
        cid: 'cozy-logo'
      }
    ]
  };
  return cozydb.api.sendMailFromUser(mailOptions, callback);
};

_getDomainAndPrepareICS = function(event, callback) {
  return async.parallel([
    function(cb) {
      return cozydb.api.getCozyDomain(cb);
    }, function(cb) {
      return User.getUserInfos(cb);
    }
  ], function(err, results) {
    var domain, icsPath, user;
    if (err) {
      return callback(err);
    }
    domain = results[0], user = results[1];
    return icsPath = _makeICSFile(event, user, function(err) {
      if (err) {
        return callback(err);
      }
      return callback(null, [domain, user, icsPath]);
    });
  });
};

module.exports.sendInvitations = function(event, dateChanged, callback) {
  var guests, htmlTemplate, needSaving, subject, subjectKey, templateKey;
  guests = event.toJSON().attendees;
  needSaving = false;
  if (dateChanged) {
    htmlTemplate = 'mail_update';
    subjectKey = 'email update title';
    templateKey = 'email update content';
  } else {
    htmlTemplate = 'mail_invite';
    subjectKey = 'email invitation title';
    templateKey = 'email invitation content';
  }
  subject = localization.t(subjectKey, {
    description: event.description
  });
  return _getDomainAndPrepareICS(event, function(err, results) {
    var domain, icsPath, user;
    if (err) {
      return callback(err);
    }
    domain = results[0], user = results[1], icsPath = results[2];
    return async.eachSeries(guests, function(guest, next) {
      var content, shouldSend, templateOptions;
      shouldSend = !guest.shareWithCozy && (guest.status === 'INVITATION-NOT-SENT' || (guest.status === 'ACCEPTED' && dateChanged));
      if (!shouldSend) {
        return next();
      }
      templateOptions = _makeTemplateOptions(event, user, domain, guest);
      content = localization.t(templateKey, templateOptions);
      return _makeMailHTML(htmlTemplate, templateOptions, function(err, html) {
        if (err) {
          return callback(err);
        }
        return _sendMail(guest, subject, html, content, function(err) {
          if (err) {
            log.error("An error occured while sending invitation");
            return log.error(err);
          } else {
            needSaving = true;
            return guest.status = 'NEEDS-ACTION';
          }
        });
      });
    }, function(err) {
      fs.unlink(icsPath, function(errUnlink) {
        if (errUnlink) {
          return log.error("Error deleting ics file " + icsPath);
        }
      });
      if (err != null) {
        return callback(err);
      } else if (!needSaving) {
        return callback();
      } else {
        return event.updateAttributes({
          attendees: guests
        }, callback);
      }
    });
  });
};

module.exports.sendDeleteNotification = function(event, callback) {
  var guests, guestsToInform;
  guests = event.toJSON().attendees;
  guestsToInform = guests.filter(function(guest) {
    var ref;
    return (ref = guest.status) === 'ACCEPTED' || ref === 'NEEDS-ACTION';
  });
  return User.getUserInfos(function(err, user) {
    if (err) {
      return callback(err);
    }
    return async.eachSeries(guestsToInform, function(guest, done) {
      var content, subject, subjectKey, templateOptions;
      templateOptions = _makeTemplateOptions(event, user);
      subjectKey = 'email delete title';
      subject = localization.t(subjectKey, {
        description: event.description
      });
      content = localization.t('email delete content', templateOptions);
      return _makeMailHTML('mail_delete', templateOptions, function(err, html) {
        if (err) {
          return callback(err);
        }
        return _sendMail(guest, subject, html, content, function(err) {
          if (err != null) {
            log.error("An error occured while sending email");
            log.error(err);
          }
          return done(err);
        });
      });
    }, callback);
  });
};

//# sourceMappingURL=mail_handler.js.map