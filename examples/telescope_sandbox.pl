#!/usr/bin/perl

use strict;
use warnings;

# telescope_sandbox.pl - a simple standalone example of how to use the 
# Astro::Telescope module to get object elevation and sun elevation information.
# Eric Saunders, February 2007.

use DateTime;
use Astro::Telescope;
use Astro::Coords;

use lib $ENV{ESTAR_PERL5LIB};
use eSTAR::ADP::Util qw( get_network_time str2datetime );

# Liverpool telescope website says:
# http://telescope.livjm.ac.uk/Info/GenInfo/specification.html
# Lat = 28.76254 degrees north = 0.502001024 radians
# Long = 17.879192 degrees west = 342.120808 degrees east = 5.97113454 radians
# Altitude = 2344m


# Create the observer location object...
#my $vt = new Astro::Telescope('JCMT');
my $vt = new Astro::Telescope(Name => 'LT simulator', Long => 5.97113454,
                              Lat  => 0.502001024,     Alt =>  2344);

#my $vt = new Astro::Telescope(Name => 'Virtual FTN', Long => 3.55604516,
#                              Lat  => 0.3620788211,     Alt =>  3055);

#my $vt = new Astro::Telescope(Name => 'Virtual FTS', Long => 2.60153048,
#                              Lat  => -0.54577638,     Alt =>  1150);

# Observatory code for La Palma. This doesn't work.
#$vt->obscode(950);

# Print the observatory details to screen...
my $name = $vt->name;
my $latitude = $vt->lat;
my $longitude = $vt->long;
my $altitude = $vt->alt;
print "**********$name***********\n";
print "*  latitude  = $latitude rads *\n";
print "*  longitude = $longitude rads  *\n";
print "*  altitude  = $altitude m           *\n";
print "*********************************\n\n";


# Create a new coords object...
my $c = new Astro::Coords( 
                            ra    => '12:29:30.4',
                            dec   => '+00:13:27.8',
                            type  => 'J2000',
                            units => 'sexagesimal'
);

# Aldebaran: 04 35 55.239 +16 30 33.49
#my $c = new Astro::Coords( 
#                            ra    => '04:35:55.239',
#                            dec   => '+16:30:33.49',
#                            type  => 'J2000',
#                            units => 'sexagesimal'
#);

# Associate the coords with the observer location...
$c->telescope( $vt );

my ($ra, $dec) = $c->radec();

print "Observation:\n";
print "   RA = $ra, Dec = $dec\n";

#my $time = $c->datetime( get_network_time() );
my $time = str2datetime('2007-04-20T04:00:00');

# Associate the coords with the time...
$c->datetime( $time );

# Set the horizon to something conservative (matches timn OBSPLAN)...
my $horizon = deg2rad(30);

my ($az, $el) = $c->azel;
print "   Azimuth = ", $az->degrees, " degrees\n";
print "   Elevation = ", $el->degrees, " degrees\n\n";



# Find the transit times of these coords...
my $rise_time = $c->rise_time( horizon => $horizon );
my $set_time  = $c->set_time( horizon => $horizon );

print "   Time = ", $time, "\n";

# Determine whether the object is in the observable sky...
is_within_limits($c->el) ? print "   Observable     (object sets at  $set_time)\n"
                         : print "   Not observable (object rises at $rise_time)\n";


# Determine whether it's dark or not...
my @dark_status = is_dark($time, $vt);
$dark_status[0] ? print "   It is night    (next sunrise at $dark_status[1])\n"
                : print "   It is day      (next sunset at  $dark_status[1])\n";

# Deduce the correct course of action...
(is_within_limits($c->el) && is_dark($time, $vt) )
   ? print "\nStatus: observation accepted.\n"
   : print "\nStatus: observation denied.\n";

# Display the ephemeris in obsplan...
#display_obsplan($ra, $dec);






# Takes an RA and Dec in sexagesimal string format, and an optional path to
# ARKDATA (obsplan data directory)  and displays the object ephemeris using the
# ARK program 'obsplan'.

#  display_obsplan($ra, $dec, [$arkdata_dir]);
sub display_obsplan {
   my $ra      = shift;
   my $dec     = shift;
   my $arkdata = shift || "$ENV{HOME}/obsplan";

   # Set the location of the datafiles used by obsplan...
   $ENV{ARKDATA} = $arkdata;
   
   # Open an outgoing pipe to obsplan...
   open my $obsplan, "|$arkdata/obsplan >& /dev/null"
                      or die "Cannot open pipe to obsplan: $!";


   # Set magic buffer autoflush on for the pipe...
   select((select($obsplan), $| = 1)[0]);

   # Tell obsplan we're sending it a target...
   print $obsplan "target\n";

   # Send obsplan the RA...
   $ra = sexegesimal2obsplan($ra);
   print $obsplan "$ra\n";

   # Send obsplan the dec...
   $dec = sexegesimal2obsplan($dec);
   print $obsplan "$dec\n";

   # Send obsplan a title for the plot...
   print $obsplan "observation\n";
   print "Press any key to close obsplan window.\n";
   chomp(my $input = <>);
   
   # Shut obsplan down cleanly...
   close_obsplan($obsplan);   
}


sub close_obsplan {
   my $obsplan_fh = shift;

   print $obsplan_fh "-1\n";
   print $obsplan_fh "\n";
   print $obsplan_fh "quit\n";
   close $obsplan_fh;
}


sub sexegesimal2obsplan {
   my $coord = shift;

   # Remove ':' from the string...
   $coord =~ s/://g;
   # Append a '.' if there isn't one (or obsplan will provide garbage)
   $coord =~ s/$/./ unless $coord =~ m/\d+[.]/;

   return $coord;
}


sub is_dark {
   my $time     = shift;
   my $telescope = shift;
   
   my $sun = new Astro::Coords(planet => 'sun');
   $sun->datetime( $time );
   $sun->telescope( $telescope );

   my $sunrise = $sun->rise_time( horizon => Astro::Coords::AST_TWILIGHT );
   my $sunset  = $sun->set_time( horizon => Astro::Coords::AST_TWILIGHT );
   
   if ( $sunrise < $sunset ) {
      return wantarray ? (1, $sunrise) : 1;
   }
   else {
      return wantarray ? (0, $sunset) : 0;
   }
}

sub is_within_limits {
   my $el = shift;
   my $min_el = deg2rad(30);

   return ( $el > $min_el ) ? 1 : 0;
}



sub deg2rad {
   my $deg = shift;
   my $pi = 3.1415926535;
   
   return $deg * $pi / 180;
}
