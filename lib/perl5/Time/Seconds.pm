# $Id: Seconds.pm,v 1.1 2004/11/12 14:32:04 aa Exp $

package Time::Seconds;
use strict;
use vars qw/@EXPORT @EXPORT_OK @ISA $VERSION/;
use UNIVERSAL qw(isa);

$VERSION = '1.01';
@ISA = 'Exporter';

@EXPORT = qw(
		ONE_MINUTE 
		ONE_HOUR 
		ONE_DAY 
		ONE_WEEK 
		ONE_MONTH
                ONE_REAL_MONTH
		ONE_YEAR
                ONE_REAL_YEAR
		ONE_FINANCIAL_MONTH
		LEAP_YEAR 
		NON_LEAP_YEAR
		);

@EXPORT_OK = qw(cs_sec cs_mon);

use constant ONE_MINUTE => 60;
use constant ONE_HOUR => 3_600;
use constant ONE_DAY => 86_400;
use constant ONE_WEEK => 604_800;
use constant ONE_MONTH => 2_629_744; # ONE_YEAR / 12
use constant ONE_REAL_MONTH => '1M';
use constant ONE_YEAR => 31_556_930; # 365.24225 days
use constant ONE_REAL_YEAR  => '1Y';
use constant ONE_FINANCIAL_MONTH => 2_592_000; # 30 days
use constant LEAP_YEAR => 31_622_400; # 366 * ONE_DAY
use constant NON_LEAP_YEAR => 31_536_000; # 365 * ONE_DAY

# hacks to make Time::Object compile once again
use constant cs_sec => 0;
use constant cs_mon => 1;

use overload 
                'fallback' => 'undef',
		'0+' => \&seconds,
		'""' => \&seconds,
		'<=>' => \&compare,
		'+' => \&add,
                '-' => \&subtract,
                '-=' => \&subtract_from,
                '+=' => \&add_to,
                '=' => \&copy;

sub new {
    my $class = shift;
    my ($val) = @_;
    $val = 0 unless defined $val;
    bless \$val, $class;
}

sub _get_ovlvals {
    my ($lhs, $rhs, $reverse) = @_;
    $lhs = $lhs->seconds;

    if (UNIVERSAL::isa($rhs, 'Time::Seconds')) {
        $rhs = $rhs->seconds;
    }
    elsif (ref($rhs)) {
        die "Can't use non Seconds object in operator overload";
    }

    if ($reverse) {
        return $rhs, $lhs;
    }

    return $lhs, $rhs;
}

sub compare {
    my ($lhs, $rhs) = _get_ovlvals(@_);
    return $lhs <=> $rhs;
}

sub add {
    my ($lhs, $rhs) = _get_ovlvals(@_);
    return Time::Seconds->new($lhs + $rhs);
}

sub add_to {
    my $lhs = shift;
    my $rhs = shift;
    $rhs = $rhs->seconds if UNIVERSAL::isa($rhs, 'Time::Seconds');
    $$lhs += $rhs;
    return $lhs;
}

sub subtract {
    my ($lhs, $rhs) = _get_ovlvals(@_);
    return Time::Seconds->new($lhs - $rhs);
}

sub subtract_from {
    my $lhs = shift;
    my $rhs = shift;
    $rhs = $rhs->seconds if UNIVERSAL::isa($rhs, 'Time::Seconds');
    $$lhs -= $rhs;
    return $lhs;
}

sub copy {
	Time::Seconds->new(${$_[0]});
}

sub seconds {
    my $s = shift;
    return $$s;
}

sub minutes {
    my $s = shift;
    return $$s / ONE_MINUTE;
}

sub hours {
    my $s = shift;
    $s->seconds / ONE_HOUR;
}

sub days {
    my $s = shift;
    $s->seconds / ONE_DAY;
}

sub weeks {
    my $s = shift;
    $s->seconds / ONE_WEEK;
}

sub months {
    my $s = shift;
    $s->seconds / ONE_MONTH;
}

sub financial_months {
    my $s = shift;
    $s->seconds / ONE_FINANCIAL_MONTH;
}

sub years {
    my $s = shift;
    $s->seconds / ONE_YEAR;
}

sub pretty_print {
    my $s = shift;
    my $fmt = shift || "h";
    $fmt = lc(substr($fmt,0,1));

    my %lut = (
	       "y" => ONE_YEAR,
	       "d" => ONE_DAY,
	       "h" => ONE_HOUR,
	       "m" => ONE_MINUTE,
	       "s" => 1.0,
	      );
    my @precedence = (qw/y d h m s/);

    # if the required format is not known convert it to "s"
    $fmt = "s" unless exists $lut{$fmt};

    my $string = '';
    my $go = 0; # indicate when to start
    my $rem = $s->seconds; # number of seconds remaining

    # Take care of any sign
    my $sgn = '';
    if ($rem < 0) {
      $rem *= -1;
      $sgn = '-';
    }

    # Now loop over each allowed format
    for my $u (@precedence) {

        # loop if we havent triggered yet
        $go = 1 if $u eq $fmt;
        next unless $go;

        # divide the current number of seconds by the number of seconds
        # in the unit and store the integer
        my $div = int( $rem / $lut{$u} );

	# calculate the new remainder
	$rem -= $div * $lut{$u};

	# append the value to the string if non-zero
	# and we havent already appended something. ie
	# do not allow 0h52m15s but do allow 1h0m2s
	$string .= $div . $u if ($div > 0 || $string);

    }

    return $sgn . $string;

}

1;
__END__

=head1 NAME

Time::Seconds - a simple API to convert seconds to other date values

=head1 SYNOPSIS

    use Time::Object;
    use Time::Seconds;
    
    my $t = localtime;
    $t += ONE_DAY;
    
    my $t2 = localtime;
    my $s = $t - $t2;
    
    print "Difference is: ", $s->days, "\n";

=head1 DESCRIPTION

This module is part of the Time::Object distribution. It allows the user
to find out the number of minutes, hours, days, weeks or years in a given
number of seconds. It is returned by Time::Object when you delta two
Time::Object objects.

Time::Seconds also exports the following constants:

    ONE_DAY
    ONE_WEEK
    ONE_HOUR
    ONE_MINUTE
    ONE_MONTH
    ONE_YEAR
    ONE_FINANCIAL_MONTH
    LEAP_YEAR
    NON_LEAP_YEAR

Since perl does not (yet?) support constant objects, these constants are in
seconds only, so you cannot, for example, do this: C<print ONE_WEEK-E<gt>minutes;>

=head1 METHODS

The following methods are available:

    my $val = Time::Seconds->new(SECONDS)
    $val->seconds;
    $val->minutes;
    $val->hours;
    $val->days;
    $val->weeks;
    $val->months;
    $val->financial_months; # 30 days
    $val->years;
    $val->pretty_print;

The methods make the assumption that there are 24 hours in a day, 7 days in
a week, 365.24225 days in a year and 12 months in a year.
(from The Calendar FAQ at http://www.tondering.dk/claus/calendar.html)

The C<pretty_print> method creates a readable version of the object.
For example, "5h32m15s" rather than 19935 seconds. Default behaviour
is to use hours, minutes and seconds. The optional argument can
be used to specify the largest unit (ie "d" would display dhms format,
"y" would display years and days). The argument can be one of
"y","d","h","m","s".

=head1 AUTHOR

Matt Sergeant, matt@sergeant.org

Tobias Brox, tobiasb@tobiasb.funcom.com

Bal�zs Szab� (dLux), dlux@kapu.hu

Tim Jenness, tjenness@cpan.org

=head1 LICENSE

Please see Time::Object for the license.

=head1 Bugs

Currently the methods aren't as efficient as they could be, for reasons of
clarity. This is probably a bad idea.

=cut
