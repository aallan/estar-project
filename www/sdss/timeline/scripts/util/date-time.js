/*==================================================
 *  Date/Time Utility Functions and Constants
 *==================================================
 */

Timeline.DateTime = new Object();

Timeline.DateTime.MILLISECOND    = 0;
Timeline.DateTime.SECOND         = 1;
Timeline.DateTime.MINUTE         = 2;
Timeline.DateTime.HOUR           = 3;
Timeline.DateTime.DAY            = 4;
Timeline.DateTime.WEEK           = 5;
Timeline.DateTime.MONTH          = 6;
Timeline.DateTime.YEAR           = 7;
Timeline.DateTime.DECADE         = 8;
Timeline.DateTime.CENTURY        = 9;
Timeline.DateTime.MILLENNIUM     = 10;

Timeline.DateTime.EPOCH          = -1;
Timeline.DateTime.ERA            = -2;

Timeline.DateTime.gregorianUnitLengths = [];
    (function() {
        var d = Timeline.DateTime;
        var a = d.gregorianUnitLengths;
        
        a[d.MILLISECOND] = 1;
        a[d.SECOND]      = 1000;
        a[d.MINUTE]      = a[d.SECOND] * 60;
        a[d.HOUR]        = a[d.MINUTE] * 60;
        a[d.DAY]         = a[d.HOUR] * 24;
        a[d.WEEK]        = a[d.DAY] * 7;
        a[d.MONTH]       = a[d.DAY] * 31;
        a[d.YEAR]        = a[d.DAY] * 365;
        a[d.DECADE]      = a[d.YEAR] * 10;
        a[d.CENTURY]     = a[d.YEAR] * 100;
        a[d.MILLENNIUM]  = a[d.YEAR] * 1000;
    })();

Timeline.DateTime.parseGregorianDateTime = function(o) {
    if (o == null) {
        return null;
    } else if (o instanceof Date) {
        return o;
    }
    
    var s = o.toString();
    if (s.length > 0 && s.length < 8) {
        var space = s.indexOf(" ");
        if (space > 0) {
            var year = parseInt(s.substr(0, space));
            var suffix = s.substr(space + 1);
            if (suffix.toLowerCase() == "bc") {
                year = 1 - year;
            }
        } else {
            var year = parseInt(s);
        }
            
        var d = new Date(0);
        d.setUTCFullYear(year);
        
        return d;
    }
    
    try {
        return new Date(Date.parse(s));
    } catch (e) {
        return null;
    }
};

Timeline.DateTime.roundDownToInterval = function(date, intervalUnit, timeZone, multiple, firstDayOfWeek) {
    var timeShift = timeZone * 
        Timeline.DateTime.gregorianUnitLengths[Timeline.DateTime.HOUR];
        
    var date2 = new Date(date.getTime() + timeShift);
    var clearInDay = function(d) {
        d.setUTCMilliseconds(0);
        d.setUTCSeconds(0);
        d.setUTCMinutes(0);
        d.setUTCHours(0);
    };
    var clearInYear = function(d) {
        clearInDay(d);
        d.setUTCDate(1);
        d.setUTCMonth(0);
    };
    
    switch(intervalUnit) {
    case Timeline.DateTime.MILLISECOND:
        var x = date2.getUTCMilliseconds();
        date2.setUTCMilliseconds(x - (x % multiple));
        break;
    case Timeline.DateTime.SECOND:
        date2.setUTCMilliseconds(0);
        
        var x = date2.getUTCSeconds();
        date2.setUTCSeconds(x - (x % multiple));
        break;
    case Timeline.DateTime.MINUTE:
        date2.setUTCMilliseconds(0);
        date2.setUTCSeconds(0);
        
        var x = date2.getUTCMinutes();
        date2.setTime(date2.getTime() - 
            (x % multiple) * Timeline.DateTime.gregorianUnitLengths[Timeline.DateTime.MINUTE]);
        break;
    case Timeline.DateTime.HOUR:
        date2.setUTCMilliseconds(0);
        date2.setUTCSeconds(0);
        date2.setUTCMinutes(0);
        
        var x = date2.getUTCHours();
        date2.setUTCHours(x - (x % multiple));
        break;
    case Timeline.DateTime.DAY:
        clearInDay(date2);
        break;
    case Timeline.DateTime.WEEK:
        clearInDay(date2);
        var d = (date2.getUTCDay() + 7 - firstDayOfWeek) % 7;
        date2.setTime(date2.getTime() - 
            d * Timeline.DateTime.gregorianUnitLengths[Timeline.DateTime.DAY]);
        break;
    case Timeline.DateTime.MONTH:
        clearInDay(date2);
        date2.setUTCDate(1);
        
        var x = date2.getUTCMonth();
        date2.setUTCMonth(x - (x % multiple));
        break;
    case Timeline.DateTime.YEAR:
        clearInYear(date2);
        
        var x = date2.getUTCFullYear();
        date2.setUTCFullYear(x - (x % multiple));
        break;
    case Timeline.DateTime.DECADE:
        clearInYear(date2);
        date2.setUTCFullYear(Math.floor(date2.getUTCFullYear() / 10) * 10);
        break;
    case Timeline.DateTime.CENTURY:
        clearInYear(date2);
        date2.setUTCFullYear(Math.floor(date2.getUTCFullYear() / 100) * 100);
        break;
    case Timeline.DateTime.MILLENNIUM:
        clearInYear(date2);
        date2.setUTCFullYear(Math.floor(date2.getUTCFullYear() / 1000) * 1000);
        break;
    }
    
    date.setTime(date2.getTime() - timeShift);
};

Timeline.DateTime.roundUpToInterval = function(date, intervalUnit, timeZone, multiple, firstDayOfWeek) {
    var originalTime = date.getTime();
    Timeline.DateTime.roundDownToInterval(date, intervalUnit, timeZone, multiple, firstDayOfWeek);
    if (date.getTime() < originalTime) {
        date.setTime(date.getTime() + 
            Timeline.DateTime.gregorianUnitLengths[intervalUnit] * multiple);
    }
};

Timeline.DateTime.incrementByInterval = function(date, intervalUnit) {
    switch(intervalUnit) {
    case Timeline.DateTime.MILLISECOND:
        date.setTime(date.getTime() + 1)
        break;
    case Timeline.DateTime.SECOND:
        date.setTime(date.getTime() + 1000);
        break;
    case Timeline.DateTime.MINUTE:
        date.setTime(date.getTime() + 
            Timeline.DateTime.gregorianUnitLengths[Timeline.DateTime.MINUTE]);
        break;
    case Timeline.DateTime.HOUR:
        date.setTime(date.getTime() + 
            Timeline.DateTime.gregorianUnitLengths[Timeline.DateTime.HOUR]);
        break;
    case Timeline.DateTime.DAY:
        date.setUTCDate(date.getUTCDate() + 1);
        break;
    case Timeline.DateTime.WEEK:
        date.setUTCDate(date.getUTCDate() + 7);
        break;
    case Timeline.DateTime.MONTH:
        date.setUTCMonth(date.getUTCMonth() + 1);
        break;
    case Timeline.DateTime.YEAR:
        date.setUTCFullYear(date.getUTCFullYear() + 1);
        break;
    case Timeline.DateTime.DECADE:
        date.setUTCFullYear(date.getUTCFullYear() + 10);
        break;
    case Timeline.DateTime.CENTURY:
        date.setUTCFullYear(date.getUTCFullYear() + 100);
        break;
    case Timeline.DateTime.MILLENNIUM:
        date.setUTCFullYear(date.getUTCFullYear() + 1000);
        break;
    }
};

Timeline.DateTime.removeTimeZoneOffset = function(date, timeZone) {
    return new Date(date.getTime() + 
        timeZone * Timeline.DateTime.gregorianUnitLengths[Timeline.DateTime.HOUR]);
};

