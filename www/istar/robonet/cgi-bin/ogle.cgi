#!/usr/bin/perl

use Time::localtime;
use Net::Domain qw(hostname hostdomain);
use LWP::UserAgent;
use Data::Dumper;

my $single = "http://estar5.astro.ex.ac.uk/robonet-1.0/cgi-bin/single.cgi";

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

$query{id} =~ s/#/%23/g;
$single = $single . "?id=$query{id}";

# G R A B    I N F O    F I L E -------------------------

#my $lwp = new LWP::UserAgent( timeout => 15 );
#$lwp->env_proxy();
#$lwp->agent( "eSTAR iPhone Robonet Script /$VERSION (". hostname() . ")" );
#my $request = new HTTP::Request(GET => $single);
#$request->authorization_basic('aa', 'wibble');
#eval { $reply = $lwp->request( $request ) };
#if ( $@ ) {
#   error( "$@" );
#   exit;
#}   

# We successfully made a request but it returned bad status
#unless ( ${$reply}{"_rc"} eq 200 ) {
#  error( "(${$reply}{_rc}): ${$reply}{_msg}");
#  exit;
#}
#my $line = ${$reply}{_content};
#my @fields = split " ", $line;
 
# we should have a reply
print "Content-type: text/html\n\n";

my $target = $query{ogle};

if ( !defined $query{plot} ) {

   print '<ul title="'.$target.'">';
   if ( $target =~ "OB" ) {
      print '<li><a href="robonet/cgi-bin/ogle.cgi?ogle='.$target.'&plot=ews">OGLE EWS</a></li>';
   }
   print '<li><a href="robonet/cgi-bin/ogle.cgi?ogle='.$target.'&plot=plens">PLENS</a></li>';
   print '<li><a href="robonet/cgi-bin/ogle.cgi?ogle='.$target.'&plot=signalmen">Signalmen</a></li>';
   print '</ul>';
   
} elsif ( $query{plot} eq "plens" ) {

   print '<div title="'.$target.'" class="panel">';
   print "<h2>PLENS</h2>";

   my $mr = 'http://robonet.lcogt.net/~robonet/newcode/EVENTS/'.$target.'.mr.gif';
   print '<div>';
   print '<img src="'.$mr.'">';
   print '</div>';

   my $c = 'http://robonet.lcogt.net/~robonet/newcode/EVENTS/'.$target.'.c.gif';
   print '<div>';
   print '<img src="'.$c.'">';
   print '</div>';

   print '</div>'; 

} elsif ( $query{plot} eq "signalmen" ) {

   print '<div title="'.$target.'" class="panel">';
   print "<h2>Signalmen</h2>";

   my $st = 'http://www.artemis-uk.org/LightCurves/'.$target.'t.gif';
   print '<div>';
   print '<img src="'.$st.'">';
   print '</div>';
 
   my $sp = 'http://www.artemis-uk.org/LightCurves/'.$target.'p.gif';
   print '<div>';
   print '<img src="'.$sp.'">';
   print '</div>';

   my $sd = 'http://www.artemis-uk.org/LightCurves/'.$target.'d.gif';
   print '<div>';
   print '<img src="'.$sd.'">';
   print '</div>'; 
 
   print '</div>'; 
} elsif ( $query{plot} eq "ews" ) {

  # OBYYXXX
  $target =~ m/OB(\d{2})(\d{3})/;
  my $url = "http://www.astrouw.edu.pl/~ogle/ogle3/ews/data";
  $url = $url . "/20$1/blg-$2";
  my $find = lc ( $url ) ."/fchart.jpg";	   
  my $curve =  lc ( $url ) ."/lcurve.gif";
  my $event =  lc ( $url ) ."/lcurve_s.gif";

  print '<div title="'.$target.'" class="panel">';
  print "<h2>OGLE EWS</h2>";
  
  print '<div>';
  print '<img src="'.$find.'">';
  print '</div>';
  print '<div>';
  print '<img src="'.$curve.'">';
  print '</div>';
  print '<div>';
  print '<img src="'.$event.'">';
  print '</div>';  

  print '</div>'; 
}

exit;
