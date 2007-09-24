#!/software/perl-5.8.6/bin/perl

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
   print 'Liverpool Telescope<br>La Palma, Spain<br><font size="-2">Lat. 28.70, Long. -17.87</font><br>'."\n";
   print '<img src="http://telescope.livjm.ac.uk/pics/webcam_int_2.jpg" width="160" height="120" alt="LT web camera" /><br>'."\n";
   my $string = "<table width='100%'>";
   foreach my $key ( sort keys %machine ) {
      my $host = "ltproxy.ing.iac.es" if $key eq "161.72.57.3";
      if ( $host =~ "iac.es" ) {
         $string = $string . "<tr><td>$host</td><td align='right'><font color='";
         if ( $machine{$key} eq "PING" ) {
            $string = $string . "lightgreen'>OK</font></td></tr>\n";
         } else {
            $string = $string . "red'>NO</font></td></tr>\n";
         }
      }
   } 
   print $string ."\n";
  
   my $lt_status = ${$node{LT}}[2];
   my $lt_status_string = "";
   if( $lt_status eq "UP" ) {
      $lt_status_string = "<font color='lightgreen'>UP</font>";
   } elsif ( $lt_status eq "DOWN" ) {
      $lt_status_string = "<font color='red'>DOWN</font>";
   } else {
      $lt_status_string = "<font color='orange'>$lt_status</font>";
   }
   print "<tr><td>Node Agent&nbsp;&nbsp;</td><td align='right'>$lt_status_string</td></tr>"; 
   print "</table>";
}

if ( $query{item} eq "FTS" ) {
   print 'Faulkes South<br>Coonabarabran, Australia<br><font size="-2">Lat. -31.27, Long. 149.28</font><br>'."\n";
   print '<img src="http://www.estar.org.uk/jpg/test_card.jpg" width="160" height="120" alt="FTS web camera" /><br>'."\n";
   my $string = "<table width='100%'>";
   foreach my $key ( sort keys %machine ) {
      my $host = "ftsproxy.aao.gov.au" if $key eq "150.203.153.202";
      if ( $host =~ "aao.gov.au" ) {
         $string = $string . "<tr><td>$host</td><td align='right'><font color='";
         if ( $machine{$key} eq "PING" ) {
            $string = $string . "lightgreen'>OK</font></td></tr>\n";
         } else {
            $string = $string . "red'>NO</font></td></tr>\n";
         }
      }
   }
   $string =  "<tr><td>ftsproxy.aao.gov.au</td><td><font color='red'>NO</font></td></tr>\n" if $string eq "";

   print $string ."\n"; 
   my $fts_status = ${$node{FTS}}[2];
   my $fts_status_string = "";
   if( $fts_status eq "UP" ) {
      $fts_status_string = "<font color='lightgreen'>UP</font>";
   } elsif ( $fts_status eq "DOWN" ) {
      $fts_status_string = "<font color='red'>DOWN</font>";
   } else {
      $fts_status_string = "<font color='orange'>$fts_status</font>";
   }
   print "<tr><td>Node Agent&nbsp;&nbsp;</td><td align='right'>$fts_status_string</td></tr>"; 
   print "</table>";
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
