#!/usr/bin/perl

use Time::localtime;
use Net::Domain qw(hostname hostdomain);
use LWP::UserAgent;
use Data::Dumper;

my $url = "http://www.estar.org.uk/network.status";

# G R A B   K E Y W O R D S ---------------------------------------------------

my $string = $ENV{QUERY_STRING};
my @pairs = split( /&/, $string );

# loop through the query string passed to the script and seperate key
# value pairs, remembering to un-Webify the munged data
my %query;
foreach my $i ( 0 ... $#pairs ) {
   my ( $name, $value ) = split( /=/, $pairs[$i] );

   # Un-Webify plus signs and %-encoding
   $value =~ tr/+/ /;
   $value =~ s/%([a-fA-F0-9][a-fA-F0-9])/pack("C", hex($1))/eg;
   $value =~ s/<!--(.|\n)*-->//g;
   $value =~ s/<([^>]|\n)*>//g;

   $query{$name} = $value;
}

# G R A B   N E T W O R K . S T A T U S   F I L E -------------------------

my $lwp = new LWP::UserAgent( timeout => 15 );
$lwp->env_proxy();
$lwp->agent( "eSTAR iPhone Status Script /$VERSION (". hostname() . ")" );
eval { $reply = $lwp->get( $url ) };
if ( $@ ) {
   error( "$@" );
   exit;
}   

# We successfully made a request but it returned bad status
unless ( ${$reply}{"_rc"} eq 200 ) {
  error( "(${$reply}{_rc}): ${$reply}{_msg}");
  exit;
}
 
# we should have a reply
my @page = split "\n", ${$reply}{_content};

# S T A T U S   I N F O R M A T I O N -------------------------------------

my $status_timestamp = $page[0];
$status_timestamp =~ s/^#\s*//;
$status_timestamp =~ s/\s*$//;

my ( %machine, %node, %ua, %broker );
my $j = 2;

# machines
while( ) {
   my @line = split " ", $page[$j];
   $machine{$line[0]} = $line[1];
   $j = $j + 1;
   last if $page[$j] =~ "#";
}

# nodes
$j = $j + 1;
while( ) {
   my @line = split " ", $page[$j];
   $node{$line[0]} = [ $line[1], $line[2], $line[3] ];
   $j = $j + 1;
   last if $page[$j] =~ "#";
}   
   

# user agents
$j = $j + 1;
while( ) {
   my @line = split " ", $page[$j];
   $ua{$line[0]} = [ $line[1], $line[2], $line[3] ];
   $j = $j + 1;
   last if $page[$j] =~ "#";
}       
 
# brokers
$j = $j + 1;
foreach my $i ( $j .. $#page ) {
   my @line = split " ", $page[$i];
   $broker{$line[0]} = [ $line[1], $line[2], $line[3] ];
}       

# G E N E R A T E   H T M L  ----------------------------------------------
print "Content-type: text/html\n\n";

if ( $query{item} eq "LT" ) {
   print '<div title="LT" class="panel">';
   print ' <div>';
   print '  <img src="http://telescope.livjm.ac.uk/pics/webcam_ext_1.jpg" />';
   print ' </div>';
   print ' <h2>Details</h2>';
   print '<fieldset>';
   print '<div class="row">';
   print '  <label>Telescope</label>';
   print '  <p>Liverpool Telescope</p>';
   print '</div>';
   print '<div class="row">';
   print '  <label>Location</label>';
   print '  <p>La Palma, Spain</p>';
   print '</div>';
   print '<div class="row">';
   print '  <label>Location</label>';
   print '  <p><a href="http://maps.google.com/staticmap?center=28.7624,-17.8792&zoom=14&size=512x512&maptype=mobile&key=ABQIAAAAE-fH9yAlvJ5m2wOajR_KXRT-tlO_4MfMkLaEL3ap_C1rBF4dfhSLxgDlKXq8dQ1gTkqm4glgwgLGbg">Lat. 28.70, Long. -17.87</a></p>';
   print '</div>';

   my $string;
   foreach my $key ( sort keys %machine ) {
      if ( $key eq "161.72.57.3" ) {
         $string = '<div class="row">';
         $string = $string . "<label>Proxy</label>";
         if ( $machine{$key} eq "PING" ) {
            $string = $string . '<p id="green">OK</p>';
         } else {
            $string = $string . '<p id="red">NO</p>';
         }
         $string = $string . '</div>';
         print $string;
      }
   } 

   print '<div class="row">';
   my $lt_status = ${$node{LT}}[2];
   my $lt_status_string = "";
   if( $lt_status eq "UP" ) {
      $lt_status_string = '<p id="green">UP</p>';
   } elsif ( $lt_status eq "DOWN" ) {
      $lt_status_string = '<p id="red">DOWN</p>';
   } else {
      $lt_status_string = '<p id="orange">'.$lt_status.'</p>';
   }
   print "<label>Agent</label>";
   print $lt_status_string; 
   print "</div>";
   print "</fieldset>";
   print "</div>";
}

if ( $query{item} eq "FTS" ) {
   print '<div title="FTS" class="panel">';
   print ' <div>';
   print '  <img src="http://www.estar.org.uk/jpg/test_card.jpg" />';
   print ' </div>';
   print ' <h2>Details</h2>';
   print '<fieldset>';
   print '<div class="row">';
   print '  <label>Telescope</label>';
   print '  <p>Faulkes South</p>';
   print '</div>';
   print '<div class="row">';
   print '  <label>Location</label>';
   print '  <p>Coonabarabran, Australia</p>';
   print '</div>';
   print '<div class="row">';
   print '  <label>Location</label>';
   print '  <p>Lat. -31.27, Long. 149.28</p>';
   print '</div>';

   my $string;
   foreach my $key ( sort keys %machine ) {
      if ( $key eq "150.203.153.202" ) {
         $string = '<div class="row">';
         $string = $string . "<label>Proxy</label>";
         if ( $machine{$key} eq "PING" ) {
            $string = $string . '<p id="green">OK</p>';
         } else {
            $string = $string . '<p id="red">NO</p>';
         }
         $string = $string . '</div>';
         print $string;
      }
   } 


   print '<div class="row">';
   my $fts_status = ${$node{LT}}[2];
   my $fts_status_string = "";
   if( $fts_status eq "UP" ) {
      $fts_status_string = '<p id="green">UP</p>';
   } elsif ( $fts_status eq "DOWN" ) {
      $fts_status_string = '<p id="red">DOWN</p>';
   } else {
      $fts_status_string = '<p id="orange">'.$fts_status.'</p>';
   }
   print "<label>Agent</label>";
   print $fts_status_string; 
   print "</div>";
   print "</fieldset>";
   print "</div>";
}

if ( $query{item} eq "FTN" ) {
   print 'Faulkes North<br>Haleakala, HI, U.S.A.<br><font size="-2">Lat. 10.7, Long. -156.2</font><br>'."\n";
   print '<img src="http://www.estar.org.uk/jpg/test_card.jpg" width="160" height="120" alt="FTN web camera" /><br>'."\n";
   my $string = "<table width='100%'>";
   foreach my $key ( sort keys %machine ) {
      my $host = "ftnproxy.ifa.hawaii.edu" if $key eq "132.160.98.239";
      if ( $host =~ "ifa.hawaii.edu" ) {
         $string = $string . "<tr><td>$host</td><td align='right'><font color='";
         if ( $machine{$key} eq "PING" ) {
            $string = $string . "lightgreen'>OK</font></td></tr>\n";
         } else {
            $string = $string . "red'>NO</font></td></tr>\n";
         }
      }
   } 
   print $string ."\n";
   my $ftn_status = ${$node{FTN}}[2];
   my $ftn_status_string = "";
   if( $ftn_status eq "UP" ) {
      $ftn_status_string = "<font color='lightgreen'>UP</font>";
   } elsif ( $ftn_status eq "DOWN" ) {
      $ftn_status_string = "<font color='red'>DOWN</font>";
   } else {
      $ftn_status_string = "<font color='orange'>$ftn_status</font>";
   }
   print "<tr><td>Node Agent&nbsp;&nbsp;</td><td align='right'>$ftn_status_string</td></tr>"; 
   print "</table>";
}

if ( $query{item} eq "UKIRT" ) {
   print 'UKIRT<br>Mauna Kea, HI, U.S.A.<br><font size="-2">Lat. 19.71, Long. -155.09</font><br>'."\n";
   print '<img width="160" height="120" src="http://www.jach.hawaii.edu/UKIRT/irtcam.jpg" alt="UKIRT web camera"><br>'."\n";
   my $string = "<table width='100%'>";
   foreach my $key ( sort keys %machine ) {
      if ( $key =~ "jach.hawaii.edu" ) {
         $string = $string . "<tr><td>$key</td><td align='right'><font color='";
         if ( $machine{$key} eq "PING" ) {
            $string = $string . "lightgreen'>OK</font></td></tr>\n";
         } else {
            $string = $string . "red'>NO</font></td></tr>\n";
         }
      }
   } 
   print $string ."\n"; 
   my $ukirt_status = ${$node{UKIRT}}[2];
   my $ukirt_status_string = "";
   if( $ukirt_status eq "UP" ) {
      $ukirt_status_string = "<font color='lightgreen'>UP</font>";
   } elsif ( $ukirt_status eq "DOWN" ) {
      $ukirt_status_string = "<font color='red'>DOWN</font>";
   } else {
      $ukirt_status_string = "<font color='orange'>$ukirt_status</font>";
   }
   print "<tr><td>Node Agent&nbsp;&nbsp;</td><td align='right'>$ukirt_status_string</td></tr>"; 
   print "</table>";
}

if ( $query{item} eq "TALONS" ) {
   print 'RAPTOR/TALONS<br>Los Alamos, NM, U.S.A.<br><font size="-2">Lat. 35.9, Long. -106.3</font><br>'."\n";
   print '<img width="160" height="120" src="http://wwc.instacam.com/InstacamImg/lsalm/02032005/020320051200_l.jpg" alt="Los Alamos web camera"><br>'."\n";
   my $raptor_status = ${$node{RAPTOR}}[2];
   my $raptor_status_string = "";
   if( $raptor_status eq "UP" ) {
      $raptor_status_string = "<font color='lightgreen'>UP</font>";
   } elsif ( $raptor_status eq "DOWN" ) {
      $raptor_status_string = "<font color='red'>DOWN</font>";
   } else {
      $raptor_status_string = "<font color='orange'>$raptor_status</font>";
   }
   print "<table width='100%'>";
   print "<tr><td>Gateway&nbsp;&nbsp;</td><td align='right'>$raptor_status_string</td></tr>";
   print "</table>";
}

exit;
