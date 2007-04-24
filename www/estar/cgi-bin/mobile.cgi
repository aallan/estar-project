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
print '<!DOCTYPE HTML PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">'."\n";
print '<html>'."\n";
print '<head>'."\n";
print '  <title>eSTAR Handheld</title>'."\n";
print '  <link rel="icon" href="http://www.estar.org.uk/favicon.ico" type="image/x-icon">'."\n";
print '  <link rel="shortcut icon" href="http://www.estar.org.uk/favicon.ico" type="image/x-icon">'."\n";

print '  <link href="http://www.estar.org.uk/pda/css/pda.css" rel="stylesheet" type="text/css" />'."\n";
print '  <meta name="HandheldFriendly" content="True" />'."\n";
print '</head>'."\n";

print '<body>'."\n";

print '<img src="http://www.estar.org.uk/pda/png/titlebar_logo.png" alt="eSTAR" border="0" height="39" width="148" /> Handheld'."\n";

print '<h1>Live Status</h1>'."\n";


print '<font color="red">'. $status_timestamp .'</font><br><br>'."\n";

# EXETER #################################################################

print '<table width="100%" border="0">'."\n"; 

print '<tr><td colspan="2"><strong style="padding-top:8px;"><font color="red">e</font>STAR</strong>, <em>Exeter, U.K.<br><font size="-2">Lat. 50.74, Long. -3.54</font></em></td></tr>'."\n";
print '<tr><td><img src="http://www.bbc.co.uk/england/webcams/live/exeter.jpg" width="160" height="120" alt="Exeter web camera" /></td><td>&nbsp</td></tr>'."\n";
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
my $adp_status = ${$ua{ADP}}[2];
my $adp_status_string = "";
if( $adp_status eq "UP" ) {
   $adp_status_string = "<font color='lightgreen'>UP</font>";
} elsif ( $adp_status eq "DOWN" ) {
   $adp_status_string = "<font color='red'>DOWN</font>";
} else {
   $adp_status_string = "<font color='orange'>$adp_status</font>";
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
print "<tr><td>ADP Programme&nbsp;&nbsp;</td><td>$adp_status_string</td></tr>"; 
print "<tr><td>Event Broker&nbsp;&nbsp;</td><td>$event_status_string</td></tr>"; 

# UKIRT #################################################################

print '<tr><td colspan="2"><hr width="100%"></td></tr>'."\n";
print '<tr><td colspan="2" style="padding-top:5px"><strong>UKIRT</strong>, <em>Hilo, HI, U.S.A.<br><font size="-2">Lat. 19.71, Long. -155.09</font></em></td></tr>'."\n";
print '<tr><td><img width="160" height="120" src="http://www.jach.hawaii.edu/UKIRT/irtcam.jpg" alt="UKIRT web camera"></td><td>&nbsp;</td></tr>'."\n";
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
print "<tr><td>Node Agent&nbsp;&nbsp;</td><td>$ukirt_status_string</td></tr>"; 

# LT ######################################################################

print '<tr><td colspan="2"><hr width="100%"></td></tr>'."\n";
print '<tr><td colspan="2" style="padding-top:5px"><strong>LT</strong>, <em>La Palma, Spain<br><font size="-2">Lat. 28.70, Long. -17.87</font></em></td></tr>'."\n";
print '<tr><td><img src="http://telescope.livjm.ac.uk/pics/webcam_int_2.jpg" width="160" height="120" alt="LT web camera" /></td><td>&nbsp;</td></tr>'."\n";
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
print "<tr><td>Node Agent&nbsp;&nbsp;</td><td>$lt_status_string</td></tr>"; 

# FTS ###################################################################

print '<tr><td colspan="2"><hr width="100%"></td></tr>'."\n";
print '<tr><td colspan="2" style="padding-top:5px"><strong>FTS</strong></strong>, <em>Coonabarabran, Australia<br><font size="-2">Lat. -31.27, Long. 149.28</font></em></td></tr>'."\n";
#print '<tr><td><img src="http://150.203.153.202:8274/axis-cgi/jpg/image.cgi?resolution=320x240" width="160" height="120" alt="FTS web camera" /></td><td>&nbsp;</td></tr>'."\n";
print '<tr><td><img src="http://www.estar.org.uk/jpg/test_card.jpg" width="160" height="120" alt="FTS web camera" /></td><td>&nbsp;</td></tr>'."\n";
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
print "<tr><td>Node Agent&nbsp;&nbsp;</td><td>$fts_status_string</td></tr>"; 

# FTN ###################################################################

print '<tr><td colspan="2"><hr width="100%"></td></tr>'."\n";
print '<tr><td colspan="2" style="padding-top:5px"><strong>Faulkes North</strong>, <em>Haleakala, HI, U.S.A.<br><font size="-2">Lat. 10.7, Long. -156.2</font></em></td></tr>'."\n";
print '<tr><td><img width="160" height="120" src="http://132.160.98.239:8275/axis-cgi/jpg/image.cgi?resolution=320x240" alt="FTN web camera"></td><td>&nbsp;</td></tr>'."\n";
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
print "<tr><td>Node Agent&nbsp;&nbsp;</td><td>$ftn_status_string</td></tr>"; 

# RAPTOR ###################################################################

print '<tr><td colspan="2"><hr width="100%"></td></tr>'."\n";
print '<tr><td colspan="2" style="padding-top:5px"><strong>RAPTOR</strong>, <em>Los Alamos, NM, U.S.A.<br><font size="-2">Lat. 35.9, Long. -106.3</font></em></td></tr>'."\n";
print '<tr><td><img width="160" height="120" src="http://wwc.instacam.com/InstacamImg/lsalm/02032005/020320051200_l.jpg" alt="Los Alamos web camera"></td><td>&nbsp;</td></tr>'."\n";
my $ftn_status = ${$node{RAPTOR}}[2];
my $ftn_status_string = "";
if( $ftn_status eq "UP" ) {
   $ftn_status_string = "<font color='lightgreen'>UP</font>";
} elsif ( $ftn_status eq "DOWN" ) {
   $ftn_status_string = "<font color='red'>DOWN</font>";
} else {
   $ftn_status_string = "<font color='orange'>$ftn_status</font>";
}
print "<tr><td>Gateway&nbsp;&nbsp;</td><td>$ftn_status_string</td></tr>";
print '<tr><td colspan="2"><hr width="100%"></td></tr>'."\n";

print '</table>'."\n";

print '<font size="-3">This page was automatically generated.<br>'."Copyright &copy; 2007 Alasdair Allan</font>\n";
print '</body>'."\n";
print '</html>'."\n";

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
 
