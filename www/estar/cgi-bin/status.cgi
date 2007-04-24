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

# G R A B   F I L E S ---------------------------------------------------------

my $header;
unless ( open ( FILE, "<../header.inc") ) {
   print "Content-type: text/html\n\n";       
   print "<HTML><HEAD>Error</HEAD><BODY>Error: Can not open header.inc file</BODY></HTML>";
   exit;
}
{
   undef $/;
   $header = <FILE>;
   close FILE;
}
$header =~ s/PAGE_TITLE_STRING/eSTAR Network Status/g;
$header =~ s/<title>/<link rel="stylesheet" HREF="..\/css\/status.css" TYPE="text\/css"><script type="text\/javascript" src="..\/js\/sticky.js"><\/script><title>/;

my $footer;
unless ( open ( FILE, "<../footer.inc") ) {
   print "Content-type: text/html\n\n";       
   print "<HTML><HEAD>Error</HEAD><BODY>Error: Can not open footer.inc file</BODY></HTML>";
   exit;
}
{
   undef $/;
   $footer = <FILE>;
   close FILE;
}
$footer =~ s/LAST_MODIFIED_DATE/ctime()/e;
$footer =~ s/ABOUT_THIS_PAGE/<font size="-3" color="grey">Code based on examples in <a href="http:\/\/www.leavethatthingalone.com\/">Seth Duffy<\/a>'s "<a href="http:\/\/www.alistapart.com\/articles\/cssmaps">A More Accessible Map<\/a>" article in <a href="http:\/\/www.alistapart.com\/">A List Apart<\/a>/;

# G R A B   N E T W O R K . S T A T U S   F I L E -------------------------

my $lwp = new LWP::UserAgent( timeout => 15 );
$lwp->env_proxy();
$lwp->agent( "eSTAR Status Map /$VERSION (". hostname() . ")" );
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


# G E N E R A T E   P A G E -----------------------------------------------

print "Content-type: text/html\n\n";
print $header;

print '<P>Network status last updated on <font color="red">'. $status_timestamp .'</font></P>'."\n";

print '<div id="holder"><dl class="map">'."\n";

# EXETER #################################################################

print '<dt><a href="http://www.astro.ex.ac.uk/" class="location" id="location01">Exeter, U.K.</a></dt>'."\n";
print '<dd><a href="javascript:void(0);" class="close"> </a>'."\n";
print '<strong><font color="red">e</font>STAR</strong><br><em>Exeter, U.K.</em><br><img src="http://www.bbc.co.uk/england/webcams/live/exeter.jpg" width="120" alt="Exeter web camera" />'."\n";
print '<a href="http://maps.google.com/maps?f=q&hl=en&q=EX4+4QL&ie=UTF8&om=1&ll=50.739008,-3.53631&spn=0.023194,0.084972&t=h">Lat. 50.74, Long. -3.54</a><br>'."\n";
print '<table>'."\n"; 
my $string = "";
foreach my $key ( sort keys %machine ) {
   if ( $key =~ "ex.ac.uk" ) {
      $string = $string . "<tr><td>$key</td><td><font color='";
      if ( $machine{$key} eq "PING" ) {
         $string = $string . "lightgreen'>OK</font></td></tr>\n";
      } else {
         $string = $string . "red'>NO</font></td></tr>\n";
      }
   }
} 
print $string ."\n";  
my $exo_status = ${$ua{"EXO-PLANET"}}[2];
my $exo_status_string = "";
if( $exo_status eq "UP" ) {
   $exo_status_string = "<font color='lightgreen'>UP</font>";
} elsif ( $exo_status eq "DOWN" ) {
   $exo_status_string = "<font color='red'>DOWN</font>";
} else {
   $exo_status_string = "<font color='orange'>$exo_status</font>";
}
my $grb_status = ${$ua{GRB}}[2];
my $grb_status_string = "";
if( $grb_status eq "UP" ) {
   $grb_status_string = "<font color='lightgreen'>UP</font>";
} elsif ( $grb_status eq "DOWN" ) {
   $grb_status_string = "<font color='red'>DOWN</font>";
} else {
   $grb_status_string = "<font color='orange'>$grb_status</font>";
}
my $event_status = ${$broker{eSTAR}}[2];
my $event_status_string = "";
if( $event_status eq "UP" ) {
   $event_status_string = "<font color='lightgreen'>UP</font>";
} elsif ( $event_status eq "DOWN" ) {
   $event_status_string = "<font color='red'>DOWN</font>";
} else {
   $event_status_string = "<font color='orange'>$event_status</font>";
}
print "<tr><td>Exo-planet Programme&nbsp;&nbsp;</td><td>$exo_status_string</td></tr>";
print "<tr><td>GRB Programme&nbsp;&nbsp;</td><td>$grb_status_string</td></tr>"; 
print "<tr><td>Event Broker&nbsp;&nbsp;</td><td>$event_status_string</td></tr></table>"; 

print '</dd>'."\n";

# UKIRT #################################################################

print '<dt><a href="http://www.jach.hawaii.edu/" class="location" id="location02">Hilo, HI, U.S.A.</a></dt>'."\n";
print '<dd><a href="javascript:void(0);" class="close"> </a>'."\n";
#print '<img src="http://www.jach.hawaii.edu/UKIRT/irtcam.jpg" width="120" alt="UKIRT web camera" />';
print '<em><strong>UKIRT</strong><br>Hilo, HI, U.S.A.</em><br><img width="120" src="http://www.jach.hawaii.edu/UKIRT/irtcam.jpg" alt="UKIRT web camera">'."\n";
print '<a href="http://maps.google.com/maps?f=q&hl=en&q=660+N.+A%27ohoku+Place,+Hilo,+Hawaii+96720&ie=UTF8&ll=19.707405,-155.089703&spn=0.069006,0.169945&t=h&om=1">Lat. 19.71, Long. -155.09</a><br>'."\n";
print '<table>'."\n"; 
my $string = "";
foreach my $key ( sort keys %machine ) {
   if ( $key =~ "jach.hawaii.edu" ) {
      $string = $string . "<tr><td>$key</td><td><font color='";
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
print "<tr><td>Node Agent&nbsp;&nbsp;</td><td>$ukirt_status_string</td></tr></table>"; 
print '</dd>'."\n";

# LT ######################################################################

print '<dt><a href="http://telescope.livjm.ac.uk/" class="location" id="location03">La Palma, Spain</a></dt>'."\n";
print '<dd><a href="javascript:void(0);" class="close"> </a>'."\n";
print '<em><strong>Liverpool Telescope</strong><br>La Palma, Spain</em><br><img src="http://telescope.livjm.ac.uk/pics/webcam_int_2.jpg" width="120" alt="LT web camera" />'."\n";
print '<a href="http://maps.google.com/?ie=UTF8&ll=28.703763,-17.866087&spn=0.128584,0.227966&t=h&om=1">Lat. 28.70, Long. -17.87</a><br>'."\n";
print '<table>'."\n"; 
my $string = "";
foreach my $key ( sort keys %machine ) {
   my $host = "ltproxy.ing.iac.es" if $key eq "161.72.57.3";
   if ( $host =~ "iac.es" ) {
      $string = $string . "<tr><td>$host</td><td><font color='";
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
print "<tr><td>Node Agent&nbsp;&nbsp;</td><td>$lt_status_string</td></tr></table>"; 
print '</dd>'."\n";

# FTS ###################################################################

print '<dt><a href="http://www.faulkes-telescope.com/" class="location" id="location04">Coonabarabran, Australia</a></dt>'."\n";
print '<dd><a href="javascript:void(0);" class="close"> </a>'."\n";
print '<em><strong>Faulkes South</strong><br>Coonabarabran, Australia</em><br><img src="http://150.203.153.202:8274/axis-cgi/jpg/image.cgi?resolution=320x240" width="120" alt="FTS web camera" />'."\n";

print '<a href="http://maps.google.com/maps?f=q&hl=en&q=coonabarabran,+Australia&ie=UTF8&ll=-31.268281,149.281883&spn=0.125305,0.33989&t=h&om=1">Lat. -31.27, Long. 149.28</a><br>'."\n";
print 'Google Earth <a href="http://www.aao.gov.au/vr/telescopes.kmz"><u>placemark file</u></a> for SSO<br>'."\n";
print '<table>'."\n"; 
my $string = "";
foreach my $key ( sort keys %machine ) {
   my $host = "ftsproxy.aao.gov.au" if $key eq "150.203.153.202";
   if ( $host =~ "aao.gov.au" ) {
      $string = $string . "<tr><td>$host</td><td><font color='";
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
print "<tr><td>Node Agent&nbsp;&nbsp;</td><td>$fts_status_string</td></tr></table>"; 
print '</dd>'."\n";

# FTN ###################################################################

print '<dt><a href="http://www.faulkes-telescope.com/" class="location" id="location05">Haleakala, HI, U.S.A.</a></dt>'."\n";
print '<dd><a href="javascript:void(0);" class="close"> </a>'."\n";
print '<em><strong>Faulkes North</strong><br>Haleakala, HI, U.S.A.</em><br><img width="120" src="http://132.160.98.239:8275/axis-cgi/jpg/image.cgi?resolution=320x240" alt="FTN web camera">'."\n";

print '<a href="http://maps.google.com/?ie=UTF8&t=h&om=1&ll=20.732997,-156.187134&spn=0.548416,0.911865">Lat. 10.7, Long. -156.2</a><br>'."\n";
print '<table>'."\n"; 
my $string = "";
foreach my $key ( sort keys %machine ) {
   my $host = "ftnproxy.ifa.hawaii.edu" if $key eq "132.160.98.239";
   if ( $host =~ "ifa.hawaii.edu" ) {
      $string = $string . "<tr><td>$host</td><td><font color='";
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
print "<tr><td>Node Agent&nbsp;&nbsp;</td><td>$ftn_status_string</td></tr></table>"; 
print '</dd>'."\n";

# RAPTOR ###################################################################

print '<dt><a href="http://www.thinkingtelescopes.lanl.gov/" class="location" id="location06">Los Alamos, NM, U.S.A.</a></dt>'."\n";
print '<dd><a href="javascript:void(0);" class="close"> </a>'."\n";
print '<em><strong>RAPTOR/TALONS</strong><br>Los Alamos, NM, U.S.A.</em><br><img width="120" src="http://wwc.instacam.com/InstacamImg/lsalm/02032005/020320051200_l.jpg" alt="Los Alamos web camera">'."\n";
print '<a href="http://maps.google.com/maps?f=q&hl=en&q=Los+Alamos,+NM&ie=UTF8&ll=35.888077,-106.306458&spn=0.095405,0.177326&t=h&om=1">Lat. 35.9, Long. -106.3</a><br>'."\n";
print '<table>'."\n";
my $ftn_status = ${$node{RAPTOR}}[2];
my $ftn_status_string = "";
if( $ftn_status eq "UP" ) {
   $ftn_status_string = "<font color='lightgreen'>UP</font>";
} elsif ( $ftn_status eq "DOWN" ) {
   $ftn_status_string = "<font color='red'>DOWN</font>";
} else {
   $ftn_status_string = "<font color='orange'>$ftn_status</font>";
}
print "<tr><td>Gateway&nbsp;&nbsp;</td><td>$ftn_status_string</td></tr></table>";
print '</dd>'."\n";


############################################################################
print '</dl>';

print '<table border="0"><tr><td><img align="right" src="../gif/download_widget.gif" /></td><td>Download the network status <a href="http://www.estar.org.uk/software/estar_status_widget.zip">Dashboard Widget</a> for Mac OS X Tiger.</td></tr></table>'."\n"; 

print "</div>\n";
print 'Latest status at information available at <a href="http://www.estar.org.uk/network.status">http://www.estar.org.uk/network.status</a><br>'."\n";

my $exo_icon_string;
if( $exo_status eq "UP" ) {
  $exo_icon_string = '<img src="../gif/icon_green.gif" />';
} elsif ( $exo_status eq "FAULT" ) {
  $exo_icon_string = '<img src="../gif/icon_yellow.gif" />';
} else {
  $exo_icon_string = '<img src="../gif/icon_red.gif" />';
}

print '<h3>Exo-planet Observing Programme&nbsp;'.$exo_icon_string.'<br><font size="-3"><em>PI: <a href="mailto:kdh1@st-andrews.ac.uk">Keith Horne</a>, University of St. Andrews</em></font></h3>'."\n";
print 'Microlensing is currently the faster and cheapest way to search for cool planets. It is this technique that is being utilised by eSTAR and <a href="http://www.astro.livjm.ac.uk/RoboNet/">RoboNet-1.0</a> to intensively monitor large numbers of Galactic Bulge microlensing events. The method is most sensitive to cool planets, 1-5 AU from the lens stars and is the only ground-based technique that is currently capable of discovering Earth-mass planets.'."\n";
print "<P>Real time status information on the <a href='http://vo.astro.ex.ac.uk/robonet-1.0/cgi-bin/status.cgi'>Robonet-1.0 Status Page</a> <img src='http://www.estar.org.uk/wiki/uploads/7/7a/Padlock_Icon.jpg' /></P>\n";

my $grb_icon_string;
if( $grb_status eq "UP" ) {
  $grb_icon_string = '<img src="../gif/icon_green.gif" />';
} elsif ( $grb_status eq "FAULT" ) {
  $grb_icon_string = '<img src="../gif/icon_yellow.gif" />';
} else {  
  $grb_icon_string = '<img src="../gif/icon_red.gif" />';
}

print '<h3>GRB Observing Programme&nbsp;'.$grb_icon_string.'<br><font size="-3"><em>PI: <a href="mailto:nrt@star.herts.ac.uk">Nial Tanvir</a>, University of Leicester</em></font></h3>'."\n";
print '<p>The eSTAR project provides a link between SWIFT and ground based telescopes by making use of the emerging field of intelligent agent technology to provide crucial autonomous decision making in software. Now deployed onto UKIRT for this purpose, it makes it the largest telescope in the world with an automatic response system for chasing GRBs.</p>'."\n";
print "<P>Real time status information on the <a href='http://grb.astro.ex.ac.uk/ukirt/cgi-bin/status.cgi'>UKIRT Status Page</a> <img src='http://www.estar.org.uk/wiki/uploads/7/7a/Padlock_Icon.jpg' /></P>\n";

print $footer;
exit;

sub timestamp {
   # ISO format 2006-01-05T08:00:00
                     
   my $year = 1900 + localtime->year();
   
   my $month = localtime->mon() + 1;
   $month = "0$month" if $month < 10;
   
   my $day = localtime->mday();
   $day = "0$day" if $day < 10;
   
   my $hour = localtime->hour();
   $hour = "0$hour" if $hour < 10;
   
   my $min = localtime->min();
   $min = "0$min" if $min < 10;
   
   my $sec = localtime->sec();
   $sec = "0$sec" if $sec < 10;
   
   my $timestamp = $year ."-". $month ."-". $day ."T". 
                   $hour .":". $min .":". $sec;

   return $timestamp;
} 

 sub error {
  my $error = shift;
  my $query = shift;
  
  print "Content-type: text/html\n\n";       
  print "<HTML><HEAD>Error</HEAD><BODY><FONT COLOR='red'>".
        "Error: $error</FONT><BR><BR>";
  if ( defined $query ) {
     print "<P><PRE>" . Dumper( $query ). "</PRE></P>";
  } 
  print "</BODY></HTML>";
}
 
